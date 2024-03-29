# frozen_string_literal: true

require 'carrierwave/orm/activerecord'

class Issue < ActiveRecord::Base
  include AtomicInternalId
  include IidRoutes
  include Issuable
  include Noteable
  include Referable
  include Spammable
  include FasterCacheKeys
  include RelativePositioning
  include TimeTrackable
  include ThrottledTouch
  include IgnorableColumn
  include LabelEventable

  ignore_column :assignee_id, :branch_name, :deleted_at

  DueDateStruct                   = Struct.new(:title, :name).freeze
  NoDueDate                       = DueDateStruct.new('No Due Date', '0').freeze
  AnyDueDate                      = DueDateStruct.new('Any Due Date', '').freeze
  Overdue                         = DueDateStruct.new('Overdue', 'overdue').freeze
  DueThisWeek                     = DueDateStruct.new('Due This Week', 'week').freeze
  DueThisMonth                    = DueDateStruct.new('Due This Month', 'month').freeze
  DueNextMonthAndPreviousTwoWeeks = DueDateStruct.new('Due Next Month And Previous Two Weeks', 'next_month_and_previous_two_weeks').freeze

  belongs_to :project
  belongs_to :moved_to, class_name: 'Issue'
  belongs_to :closed_by, class_name: 'User'

  has_internal_id :iid, scope: :project, init: ->(s) { s&.project&.issues&.maximum(:iid) }

  has_many :events, as: :target, dependent: :destroy # rubocop:disable Cop/ActiveRecordDependent

  has_many :merge_requests_closing_issues,
    class_name: 'MergeRequestsClosingIssues',
    dependent: :delete_all # rubocop:disable Cop/ActiveRecordDependent

  has_many :issue_assignees
  has_many :assignees, class_name: "User", through: :issue_assignees

  validates :project, presence: true

  alias_attribute :parent_ids, :project_id

  scope :in_projects, ->(project_ids) { where(project_id: project_ids) }

  scope :assigned, -> { where('EXISTS (SELECT TRUE FROM issue_assignees WHERE issue_id = issues.id)') }
  scope :unassigned, -> { where('NOT EXISTS (SELECT TRUE FROM issue_assignees WHERE issue_id = issues.id)') }
  scope :assigned_to, ->(u) { where('EXISTS (SELECT TRUE FROM issue_assignees WHERE user_id = ? AND issue_id = issues.id)', u.id)}

  scope :with_due_date, -> { where.not(due_date: nil) }
  scope :without_due_date, -> { where(due_date: nil) }
  scope :due_before, ->(date) { where('issues.due_date < ?', date) }
  scope :due_between, ->(from_date, to_date) { where('issues.due_date >= ?', from_date).where('issues.due_date <= ?', to_date) }
  scope :due_tomorrow, -> { where(due_date: Date.tomorrow) }

  scope :order_due_date_asc, -> { reorder('issues.due_date IS NULL, issues.due_date ASC') }
  scope :order_due_date_desc, -> { reorder('issues.due_date IS NULL, issues.due_date DESC') }
  scope :order_closest_future_date, -> { reorder('CASE WHEN issues.due_date >= CURRENT_DATE THEN 0 ELSE 1 END ASC, ABS(CURRENT_DATE - issues.due_date) ASC') }

  scope :preload_associations, -> { preload(:labels, project: :namespace) }

  scope :public_only, -> { where(confidential: false) }

  after_save :expire_etag_cache
  after_save :ensure_metrics, unless: :imported?

  attr_spammable :title, spam_title: true
  attr_spammable :description, spam_description: true

  participant :assignees

  state_machine :state, initial: :opened do
    event :close do
      transition [:opened] => :closed
    end

    event :reopen do
      transition closed: :opened
    end

    state :opened
    state :closed

    before_transition any => :closed do |issue|
      issue.closed_at = Time.zone.now
    end

    before_transition closed: :opened do |issue|
      issue.closed_at = nil
      issue.closed_by = nil
    end
  end

  class << self
    alias_method :in_parents, :in_projects
  end

  def self.parent_column
    :project_id
  end

  def self.reference_prefix
    '#'
  end

  # Pattern used to extract `#123` issue references from text
  #
  # This pattern supports cross-project references.
  def self.reference_pattern
    @reference_pattern ||= %r{
      (#{Project.reference_pattern})?
      #{Regexp.escape(reference_prefix)}(?<issue>\d+)
    }x
  end

  def self.link_reference_pattern
    @link_reference_pattern ||= super("issues", /(?<issue>\d+)/)
  end

  def self.reference_valid?(reference)
    reference.to_i > 0 && reference.to_i <= Gitlab::Database::MAX_INT_VALUE
  end

  def self.project_foreign_key
    'project_id'
  end

  def self.sort_by_attribute(method, excluded_labels: [])
    case method.to_s
    when 'closest_future_date' then order_closest_future_date
    when 'due_date'      then order_due_date_asc
    when 'due_date_asc'  then order_due_date_asc
    when 'due_date_desc' then order_due_date_desc
    else
      super
    end
  end

  def self.order_by_position_and_priority
    order_labels_priority
      .reorder(Gitlab::Database.nulls_last_order('relative_position', 'ASC'),
              Gitlab::Database.nulls_last_order('highest_priority', 'ASC'),
              "id DESC")
  end

  def hook_attrs
    Gitlab::HookData::IssueBuilder.new(self).build
  end

  # Returns a Hash of attributes to be used for Twitter card metadata
  def card_attributes
    {
      'Author'   => author.try(:name),
      'Assignee' => assignee_list
    }
  end

  def assignee_or_author?(user)
    author_id == user.id || assignees.exists?(user.id)
  end

  def assignee_list
    assignees.map(&:name).to_sentence
  end

  # `from` argument can be a Namespace or Project.
  def to_reference(from = nil, full: false)
    reference = "#{self.class.reference_prefix}#{iid}"

    "#{project.to_reference(from, full: full)}#{reference}"
  end

  def suggested_branch_name
    return to_branch_name unless project.repository.branch_exists?(to_branch_name)

    start_counting_from = 2
    Uniquify.new(start_counting_from).string(-> (counter) { "#{to_branch_name}-#{counter}" }) do |suggested_branch_name|
      project.repository.branch_exists?(suggested_branch_name)
    end
  end

  # Returns boolean if a related branch exists for the current issue
  # ignores merge requests branchs
  def has_related_branch?
    project.repository.branch_names.any? do |branch|
      /\A#{iid}-(?!\d+-stable)/i =~ branch
    end
  end

  # To allow polymorphism with MergeRequest.
  def source_project
    project
  end

  def state_human_name
    if closed?
      "已关闭"
    else
      "未关闭"
    end
  end

  def zh_name
    '问题'
  end
  def moved?
    !moved_to.nil?
  end

  def can_move?(user, to_project = nil)
    if to_project
      return false unless user.can?(:admin_issue, to_project)
    end

    !moved? && persisted? &&
      user.can?(:admin_issue, self.project)
  end

  def to_branch_name
    if self.confidential?
      "#{iid}-confidential-issue"
    else
      "#{iid}-#{title.parameterize}"
    end
  end

  def can_be_worked_on?
    !self.closed? && !self.project.forked?
  end

  # Returns `true` if the current issue can be viewed by either a logged in User
  # or an anonymous user.
  def visible_to_user?(user = nil)
    return false unless project && project.feature_available?(:issues, user)

    user ? readable_by?(user) : publicly_visible?
  end

  def check_for_spam?
    project.public? && (title_changed? || description_changed?)
  end

  def as_json(options = {})
    super(options).tap do |json|
      if options.key?(:labels)
        json[:labels] = labels.as_json(
          project: project,
          only: [:id, :title, :description, :color, :priority],
          methods: [:text_color]
        )
      end
    end
  end

  def etag_caching_enabled?
    true
  end

  def discussions_rendered_on_frontend?
    true
  end

  # rubocop: disable CodeReuse/ServiceClass
  def update_project_counter_caches
    Projects::OpenIssuesCountService.new(project).refresh_cache
  end
  # rubocop: enable CodeReuse/ServiceClass

  private

  def ensure_metrics
    super
    metrics.record!
  end

  # Returns `true` if the given User can read the current Issue.
  #
  # This method duplicates the same check of issue_policy.rb
  # for performance reasons, check commit: 002ad215818450d2cbbc5fa065850a953dc7ada8
  # Make sure to sync this method with issue_policy.rb
  def readable_by?(user)
    if user.admin?
      true
    elsif project.owner == user
      true
    elsif confidential?
      author == user ||
        assignees.include?(user) ||
        project.team.member?(user, Gitlab::Access::REPORTER)
    else
      project.public? ||
        project.internal? && !user.external? ||
        project.team.member?(user)
    end
  end

  # Returns `true` if this Issue is visible to everybody.
  def publicly_visible?
    project.public? && !confidential?
  end

  def expire_etag_cache
    key = Gitlab::Routing.url_helpers.realtime_changes_project_issue_path(project, self)
    Gitlab::EtagCaching::Store.new.touch(key)
  end
end
