# frozen_string_literal: true

class FlowdockService < Service
  prop_accessor :token
  validates :token, presence: true, if: :activated?

  def title
    'Flowdock'
  end

  def description
    'Flowdock 是一个为技术团队设计的 Web 协作应用'
  end

  def self.to_param
    'flowdock'
  end

  def fields
    [
      { type: 'text', name: 'token', placeholder: 'Flowdock Git source token', required: true }
    ]
  end

  def self.supported_events
    %w(push)
  end

  def execute(data)
    return unless supported_events.include?(data[:object_kind])

    Flowdock::Git.post(
      data[:ref],
      data[:before],
      data[:after],
      token: token,
      repo: project.repository,
      repo_url: "#{Gitlab.config.gitlab.url}/#{project.full_path}",
      commit_url: "#{Gitlab.config.gitlab.url}/#{project.full_path}/commit/%s",
      diff_url: "#{Gitlab.config.gitlab.url}/#{project.full_path}/compare/%s...%s"
    )
  end
end
