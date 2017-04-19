class Admin::SpamLogsController < Admin::ApplicationController
  def index
    @spam_logs = SpamLog.order(id: :desc).page(params[:page])
  end

  def destroy
    spam_log = SpamLog.find(params[:id])

    if params[:remove_user]
      spam_log.remove_user(deleted_by: current_user)
      redirect_to admin_spam_logs_path, notice: "用户 #{spam_log.user.username} 删除成功。"
    else
      spam_log.destroy
      head :ok
    end
  end

  def mark_as_ham
    spam_log = SpamLog.find(params[:id])

    if HamService.new(spam_log).mark_as_ham!
      redirect_to admin_spam_logs_path, notice: 'Spam log successfully submitted as ham.'
    else
      redirect_to admin_spam_logs_path, alert: 'Error with Akismet. Please check the logs for more info.'
    end
  end
end
