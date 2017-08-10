class Admin::ProjectsController < Admin::ApplicationController
  before_action :project, only: [:show, :transfer, :repository_check]
  before_action :group, only: [:show, :transfer]

  def index
    finder    = Admin::ProjectsFinder.new(params: params, current_user: current_user)
    @projects = finder.execute
    @sort     = finder.sort

    respond_to do |format|
      format.html
      format.json do
        render json: {
          html: view_to_html_string("admin/projects/_projects", locals: { projects: @projects })
        }
      end
    end
  end

  def show
    if @group
      @group_members = @group.members.order("access_level DESC").page(params[:group_members_page])
    end

    @project_members = @project.members.page(params[:project_members_page])
    @requesters = AccessRequestsFinder.new(@project).execute(current_user)
  end

  def transfer
    namespace = Namespace.find_by(id: params[:new_namespace_id])
    ::Projects::TransferService.new(@project, current_user, params.dup).execute(namespace)

    @project.reload
    redirect_to admin_project_path(@project)
  end

  def repository_check
    RepositoryCheck::SingleRepositoryWorker.perform_async(@project.id)

    redirect_to(
      admin_project_path(@project),
      notice: '版本仓库检查已触发。'
    )
  end

  protected

  def project
    @project = Project.find_by_full_path(
      [params[:namespace_id], '/', params[:id]].join('')
    )
    @project || render_404
  end

  def group
    @group ||= @project.group
  end
end
