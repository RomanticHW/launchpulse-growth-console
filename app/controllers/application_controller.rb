class ApplicationController < ActionController::Base
  # Only allow modern browsers supporting webp images, web push, badges, import maps, CSS nesting, and CSS :has.
  allow_browser versions: :modern

  # Changes to the importmap will invalidate the etag for HTML responses
  stale_when_importmap_changes

  before_action :require_user
  helper_method :current_user, :current_account

  private

  def current_user
    @current_user ||= User.find_by(id: session[:user_id])
  end

  def current_account
    @current_account ||= current_user&.accounts&.first
  end

  def require_user
    if current_user.blank?
      redirect_to new_session_path
    elsif current_account.blank?
      reset_session
      redirect_to new_session_path, alert: "请先加入一个账户。"
    end
  end
end
