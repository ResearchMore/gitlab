# frozen_string_literal: true

##
# DEPRECATED
#
# These helpers are deprecated in favor of detailed CI/CD statuses.
#
# See 'detailed_status?` method and `Gitlab::Ci::Status` module.
#
module CiStatusHelper
  def ci_status_zh(status)
    case status
      when 'pending'
        '排队'
      when 'running'
        '运行'
      when 'failed'
        '失败'
      when 'canceled'
        '取消'
      else
         '未知'
    end
  end

  def ci_stage_zh(stage)
    case stage
      when 'build'
        '构建'
      when 'deploy'
        '部署'
      when 'test'
        '测试'
      else
        stage.titleize
    end
  end
  def ci_label_for_status(status)
    if detailed_status?(status)
      return status.label
    end

    label = case status
            when 'success'
              'passed'
            when 'success_with_warnings'
              'passed with warnings'
            when 'manual'
              'waiting for manual action'
            when 'scheduled'
              'waiting for delayed job'
            else
              status
            end
    translation = "CiStatusLabel|#{label}"
    s_(translation)
  end

  def ci_text_for_status(status)
    if detailed_status?(status)
      return status.text
    end

    case status
    when 'success'
      s_('CiStatusText|passed')
    when 'success_with_warnings'
      s_('CiStatusText|passed')
    when 'manual'
      s_('CiStatusText|blocked')
    when 'scheduled'
      s_('CiStatusText|delayed')
    else
      # All states are already being translated inside the detailed statuses:
      # :running => Gitlab::Ci::Status::Running
      # :skipped => Gitlab::Ci::Status::Skipped
      # :failed => Gitlab::Ci::Status::Failed
      # :success => Gitlab::Ci::Status::Success
      # :canceled => Gitlab::Ci::Status::Canceled
      # The following states are customized above:
      # :manual => Gitlab::Ci::Status::Manual
      status_translation = "CiStatusText|#{status}"
      s_(status_translation)
    end
  end

  def ci_status_for_statuseable(subject)
    status = subject.try(:status) || 'not found'
    status.humanize
  end

  def ci_icon_for_status(status, size: 16)
    if detailed_status?(status)
      return sprite_icon(status.icon)
    end

    icon_name =
      case status
      when 'success'
        'status_success'
      when 'success_with_warnings'
        'status_warning'
      when 'failed'
        'status_failed'
      when 'pending'
        'status_pending'
      when 'running'
        'status_running'
      when 'play'
        'play'
      when 'created'
        'status_created'
      when 'skipped'
        'status_skipped'
      when 'manual'
        'status_manual'
      when 'scheduled'
        'status_scheduled'
      else
        'status_canceled'
      end

    sprite_icon(icon_name, size: size)
  end

  def pipeline_status_cache_key(pipeline_status)
    "pipeline-status/#{pipeline_status.sha}-#{pipeline_status.status}"
  end

  def render_project_pipeline_status(pipeline_status, tooltip_placement: 'left')
    project = pipeline_status.project
    path = pipelines_project_commit_path(project, pipeline_status.sha, ref: pipeline_status.ref)

    render_status_with_link(
      'commit',
      pipeline_status.status,
      path,
      tooltip_placement: tooltip_placement)
  end

  def render_commit_status(commit, ref: nil, tooltip_placement: 'left')
    project = commit.project
    path = pipelines_project_commit_path(project, commit, ref: ref)

    render_status_with_link(
      'commit',
      commit.status(ref),
      path,
      tooltip_placement: tooltip_placement,
      icon_size: 24)
  end

  def render_pipeline_status(pipeline, tooltip_placement: 'left')
    project = pipeline.project
    path = project_pipeline_path(project, pipeline)
    render_status_with_link('pipeline', pipeline.status, path, tooltip_placement: tooltip_placement)
  end

  def render_status_with_link(type, status, path = nil, tooltip_placement: 'left', cssclass: '', container: 'body', icon_size: 16)
    klass = "ci-status-link ci-status-icon-#{status.dasherize} #{cssclass}"
    title = "#{type.titleize}: #{ci_label_for_status(status)}"
    data = { toggle: 'tooltip', placement: tooltip_placement, container: container }

    if path
      link_to ci_icon_for_status(status, size: icon_size), path,
              class: klass, title: title, data: data
    else
      content_tag :span, ci_icon_for_status(status, size: icon_size),
              class: klass, title: title, data: data
    end
  end

  def detailed_status?(status)
    status.respond_to?(:text) &&
      status.respond_to?(:label) &&
      status.respond_to?(:icon)
  end
end
