require 'spec_helper'

describe ProjectPolicy do
  set(:guest) { create(:user) }
  set(:reporter) { create(:user) }
  set(:developer) { create(:user) }
  set(:maintainer) { create(:user) }
  set(:owner) { create(:user) }
  set(:admin) { create(:admin) }
  let(:project) { create(:project, :public, namespace: owner.namespace) }

  let(:base_guest_permissions) do
    %i[
      read_project read_board read_list read_wiki read_issue
      read_project_for_iids read_issue_iid read_label
      read_milestone read_project_snippet read_project_member read_note
      create_project create_issue create_note upload_file create_merge_request_in
      award_emoji
    ]
  end

  let(:base_reporter_permissions) do
    %i[
      download_code fork_project create_project_snippet update_issue
      admin_issue admin_label admin_list read_commit_status read_build
      read_container_image read_pipeline read_environment read_deployment
      read_merge_request download_wiki_code read_sentry_issue read_release
    ]
  end

  let(:team_member_reporter_permissions) do
    %i[build_download_code build_read_container_image]
  end

  let(:developer_permissions) do
    %i[
      admin_milestone admin_merge_request update_merge_request create_commit_status
      update_commit_status create_build update_build create_pipeline
      update_pipeline create_merge_request_from create_wiki push_code
      resolve_note create_container_image update_container_image
      create_environment create_deployment create_release update_release
    ]
  end

  let(:base_maintainer_permissions) do
    %i[
      push_to_delete_protected_branch update_project_snippet update_environment
      update_deployment admin_project_snippet
      admin_project_member admin_note admin_wiki admin_project
      admin_commit_status admin_build admin_container_image
      admin_pipeline admin_environment admin_deployment destroy_release add_cluster
    ]
  end

  let(:public_permissions) do
    %i[
      download_code fork_project read_commit_status read_pipeline
      read_container_image build_download_code build_read_container_image
      download_wiki_code read_release
    ]
  end

  let(:owner_permissions) do
    %i[
      change_namespace change_visibility_level rename_project remove_project
      archive_project remove_fork_project destroy_merge_request destroy_issue
      set_issue_iid set_issue_created_at set_note_created_at
    ]
  end

  # Used in EE specs
  let(:additional_guest_permissions)  { [] }
  let(:additional_reporter_permissions) { [] }
  let(:additional_maintainer_permissions) { [] }

  let(:guest_permissions) { base_guest_permissions + additional_guest_permissions }
  let(:reporter_permissions) { base_reporter_permissions + additional_reporter_permissions }
  let(:maintainer_permissions) { base_maintainer_permissions + additional_maintainer_permissions }

  before do
    project.add_guest(guest)
    project.add_maintainer(maintainer)
    project.add_developer(developer)
    project.add_reporter(reporter)
  end

  def expect_allowed(*permissions)
    permissions.each { |p| is_expected.to be_allowed(p) }
  end

  def expect_disallowed(*permissions)
    permissions.each { |p| is_expected.not_to be_allowed(p) }
  end

  it 'does not include the read_issue permission when the issue author is not a member of the private project' do
    project = create(:project, :private)
    issue   = create(:issue, project: project, author: create(:user))
    user    = issue.author

    expect(project.team.member?(issue.author)).to be false

    expect(Ability).not_to be_allowed(user, :read_issue, project)
  end

  context 'wiki feature' do
    let(:permissions) { %i(read_wiki create_wiki update_wiki admin_wiki download_wiki_code) }

    subject { described_class.new(owner, project) }

    context 'when the feature is disabled' do
      before do
        project.project_feature.update_attribute(:wiki_access_level, ProjectFeature::DISABLED)
      end

      it 'does not include the wiki permissions' do
        expect_disallowed(*permissions)
      end

      context 'when there is an external wiki' do
        it 'does not include the wiki permissions' do
          allow(project).to receive(:has_external_wiki?).and_return(true)

          expect_disallowed(*permissions)
        end
      end
    end
  end

  context 'issues feature' do
    subject { described_class.new(owner, project) }

    context 'when the feature is disabled' do
      before do
        project.issues_enabled = false
        project.save!
      end

      it 'does not include the issues permissions' do
        expect_disallowed :read_issue, :read_issue_iid, :create_issue, :update_issue, :admin_issue
      end

      it 'disables boards and lists permissions' do
        expect_disallowed :read_board, :create_board, :update_board, :admin_board
        expect_disallowed :read_list, :create_list, :update_list, :admin_list
      end

      context 'when external tracker configured' do
        it 'does not include the issues permissions' do
          create(:jira_service, project: project)

          expect_disallowed :read_issue, :read_issue_iid, :create_issue, :update_issue, :admin_issue
        end
      end
    end
  end

  context 'merge requests feature' do
    subject { described_class.new(owner, project) }

    it 'disallows all permissions when the feature is disabled' do
      project.project_feature.update(merge_requests_access_level: ProjectFeature::DISABLED)

      mr_permissions = [:create_merge_request_from, :read_merge_request,
                        :update_merge_request, :admin_merge_request,
                        :create_merge_request_in]

      expect_disallowed(*mr_permissions)
    end
  end

  context 'for a guest in a private project' do
    let(:project) { create(:project, :private) }
    subject { described_class.new(guest, project) }

    it 'disallows the guest from reading the merge request and merge request iid' do
      expect_disallowed(:read_merge_request)
      expect_disallowed(:read_merge_request_iid)
    end
  end

  context 'builds feature' do
    context 'when builds are disabled' do
      subject { described_class.new(owner, project) }

      before do
        project.project_feature.update(builds_access_level: ProjectFeature::DISABLED)
      end

      it 'disallows all permissions except pipeline when the feature is disabled' do
        builds_permissions = [
          :create_build, :read_build, :update_build, :admin_build, :destroy_build,
          :create_pipeline_schedule, :read_pipeline_schedule, :update_pipeline_schedule, :admin_pipeline_schedule, :destroy_pipeline_schedule,
          :create_environment, :read_environment, :update_environment, :admin_environment, :destroy_environment,
          :create_cluster, :read_cluster, :update_cluster, :admin_cluster, :destroy_cluster,
          :create_deployment, :read_deployment, :update_deployment, :admin_deployment, :destroy_deployment
        ]

        expect_disallowed(*builds_permissions)
      end
    end

    context 'when builds are disabled only for some users' do
      subject { described_class.new(guest, project) }

      before do
        project.project_feature.update(builds_access_level: ProjectFeature::PRIVATE)
      end

      it 'disallows pipeline and commit_status permissions' do
        builds_permissions = [
          :create_pipeline, :update_pipeline, :admin_pipeline, :destroy_pipeline,
          :create_commit_status, :update_commit_status, :admin_commit_status, :destroy_commit_status
        ]

        expect_disallowed(*builds_permissions)
      end
    end
  end

  context 'repository feature' do
    subject { described_class.new(owner, project) }

    it 'disallows all permissions when the feature is disabled' do
      project.project_feature.update(repository_access_level: ProjectFeature::DISABLED)

      repository_permissions = [
        :create_pipeline, :update_pipeline, :admin_pipeline, :destroy_pipeline,
        :create_build, :read_build, :update_build, :admin_build, :destroy_build,
        :create_pipeline_schedule, :read_pipeline_schedule, :update_pipeline_schedule, :admin_pipeline_schedule, :destroy_pipeline_schedule,
        :create_environment, :read_environment, :update_environment, :admin_environment, :destroy_environment,
        :create_cluster, :read_cluster, :update_cluster, :admin_cluster,
        :create_deployment, :read_deployment, :update_deployment, :admin_deployment, :destroy_deployment,
        :destroy_release
      ]

      expect_disallowed(*repository_permissions)
    end
  end

  shared_examples 'archived project policies' do
    let(:feature_write_abilities) do
      described_class::READONLY_FEATURES_WHEN_ARCHIVED.flat_map do |feature|
        described_class.create_update_admin_destroy(feature)
      end
    end

    let(:other_write_abilities) do
      %i[
        create_merge_request_in
        create_merge_request_from
        push_to_delete_protected_branch
        push_code
        request_access
        upload_file
        resolve_note
        award_emoji
      ]
    end

    context 'when the project is archived' do
      before do
        project.archived = true
      end

      it 'disables write actions on all relevant project features' do
        expect_disallowed(*feature_write_abilities)
      end

      it 'disables some other important write actions' do
        expect_disallowed(*other_write_abilities)
      end

      it 'does not disable other abilities' do
        expect_allowed(*(regular_abilities - feature_write_abilities - other_write_abilities))
      end
    end
  end

  shared_examples 'project policies as anonymous' do
    context 'abilities for public projects' do
      context 'when a project has pending invites' do
        let(:group) { create(:group, :public) }
        let(:project) { create(:project, :public, namespace: group) }
        let(:user_permissions) { [:create_merge_request_in, :create_project, :create_issue, :create_note, :upload_file, :award_emoji] }
        let(:anonymous_permissions) { guest_permissions - user_permissions  }

        subject { described_class.new(nil, project) }

        before do
          create(:group_member, :invited, group: group)
        end

        it 'does not grant owner access' do
          expect_allowed(*anonymous_permissions)
          expect_disallowed(*user_permissions)
        end

        it_behaves_like 'archived project policies' do
          let(:regular_abilities) { anonymous_permissions }
        end
      end
    end

    context 'abilities for non-public projects' do
      let(:project) { create(:project, namespace: owner.namespace) }

      subject { described_class.new(nil, project) }

      it { is_expected.to be_banned }
    end
  end

  shared_examples 'project policies as guest' do
    subject { described_class.new(guest, project) }

    context 'abilities for non-public projects' do
      let(:project) { create(:project, namespace: owner.namespace) }
      let(:reporter_public_build_permissions) do
        reporter_permissions - [:read_build, :read_pipeline]
      end

      it do
        expect_allowed(*guest_permissions)
        expect_disallowed(*reporter_public_build_permissions)
        expect_disallowed(*team_member_reporter_permissions)
        expect_disallowed(*developer_permissions)
        expect_disallowed(*maintainer_permissions)
        expect_disallowed(*owner_permissions)
      end

      it_behaves_like 'archived project policies' do
        let(:regular_abilities) { guest_permissions }
      end

      context 'public builds enabled' do
        it do
          expect_allowed(*guest_permissions)
          expect_allowed(:read_build, :read_pipeline)
        end
      end

      context 'when public builds disabled' do
        before do
          project.update(public_builds: false)
        end

        it do
          expect_allowed(*guest_permissions)
          expect_disallowed(:read_build, :read_pipeline)
        end
      end

      context 'when builds are disabled' do
        before do
          project.project_feature.update(builds_access_level: ProjectFeature::DISABLED)
        end

        it do
          expect_disallowed(:read_build)
          expect_allowed(:read_pipeline)
        end
      end
    end
  end

  shared_examples 'project policies as reporter' do
    context 'abilities for non-public projects' do
      let(:project) { create(:project, namespace: owner.namespace) }

      subject { described_class.new(reporter, project) }

      it do
        expect_allowed(*guest_permissions)
        expect_allowed(*reporter_permissions)
        expect_allowed(*team_member_reporter_permissions)
        expect_disallowed(*developer_permissions)
        expect_disallowed(*maintainer_permissions)
        expect_disallowed(*owner_permissions)
      end

      it_behaves_like 'archived project policies' do
        let(:regular_abilities) { reporter_permissions }
      end
    end
  end

  shared_examples 'project policies as developer' do
    context 'abilities for non-public projects' do
      let(:project) { create(:project, namespace: owner.namespace) }

      subject { described_class.new(developer, project) }

      it do
        expect_allowed(*guest_permissions)
        expect_allowed(*reporter_permissions)
        expect_allowed(*team_member_reporter_permissions)
        expect_allowed(*developer_permissions)
        expect_disallowed(*maintainer_permissions)
        expect_disallowed(*owner_permissions)
      end

      it_behaves_like 'archived project policies' do
        let(:regular_abilities) { developer_permissions }
      end
    end
  end

  shared_examples 'project policies as maintainer' do
    context 'abilities for non-public projects' do
      let(:project) { create(:project, namespace: owner.namespace) }

      subject { described_class.new(maintainer, project) }

      it do
        expect_allowed(*guest_permissions)
        expect_allowed(*reporter_permissions)
        expect_allowed(*team_member_reporter_permissions)
        expect_allowed(*developer_permissions)
        expect_allowed(*maintainer_permissions)
        expect_disallowed(*owner_permissions)
      end

      it_behaves_like 'archived project policies' do
        let(:regular_abilities) { maintainer_permissions }
      end
    end
  end

  shared_examples 'project policies as owner' do
    context 'abilities for non-public projects' do
      let(:project) { create(:project, namespace: owner.namespace) }

      subject { described_class.new(owner, project) }

      it do
        expect_allowed(*guest_permissions)
        expect_allowed(*reporter_permissions)
        expect_allowed(*team_member_reporter_permissions)
        expect_allowed(*developer_permissions)
        expect_allowed(*maintainer_permissions)
        expect_allowed(*owner_permissions)
      end

      it_behaves_like 'archived project policies' do
        let(:regular_abilities) { owner_permissions }
      end
    end
  end

  shared_examples 'project policies as admin' do
    context 'abilities for non-public projects' do
      let(:project) { create(:project, namespace: owner.namespace) }

      subject { described_class.new(admin, project) }

      it do
        expect_allowed(*guest_permissions)
        expect_allowed(*reporter_permissions)
        expect_disallowed(*team_member_reporter_permissions)
        expect_allowed(*developer_permissions)
        expect_allowed(*maintainer_permissions)
        expect_allowed(*owner_permissions)
      end

      it_behaves_like 'archived project policies' do
        let(:regular_abilities) { owner_permissions }
      end
    end
  end

  it_behaves_like 'project policies as anonymous'
  it_behaves_like 'project policies as guest'
  it_behaves_like 'project policies as reporter'
  it_behaves_like 'project policies as developer'
  it_behaves_like 'project policies as maintainer'
  it_behaves_like 'project policies as owner'
  it_behaves_like 'project policies as admin'

  context 'when a public project has merge requests allowing access' do
    include ProjectForksHelper
    let(:user) { create(:user) }
    let(:target_project) { create(:project, :public) }
    let(:project) { fork_project(target_project) }
    let!(:merge_request) do
      create(
        :merge_request,
        target_project: target_project,
        source_project: project,
        allow_collaboration: true
      )
    end
    let(:maintainer_abilities) do
      %w(create_build create_pipeline)
    end

    subject { described_class.new(user, project) }

    it 'does not allow pushing code' do
      expect_disallowed(*maintainer_abilities)
    end

    it 'allows pushing if the user is a member with push access to the target project' do
      target_project.add_developer(user)

      expect_allowed(*maintainer_abilities)
    end

    it 'dissallows abilities to a maintainer if the merge request was closed' do
      target_project.add_developer(user)
      merge_request.close!

      expect_disallowed(*maintainer_abilities)
    end
  end

  it_behaves_like 'clusterable policies' do
    let(:clusterable) { create(:project, :repository) }
    let(:cluster) do
      create(:cluster,
             :provided_by_gcp,
             :project,
             projects: [clusterable])
    end
  end
end
