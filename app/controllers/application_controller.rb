class ApplicationController < ActionController::Base
  # Only allow modern browsers supporting webp images, web push, badges, import maps, CSS nesting, and CSS :has.
  allow_browser versions: :modern

  # Changes to the importmap will invalidate the etag for HTML responses
  stale_when_importmap_changes

  before_action :require_user
  helper_method :current_user, :current_account, :current_membership

  private

  def current_user
    @current_user ||= User.find_by(id: session[:user_id])
  end

  def current_account
    @current_account ||= current_user&.accounts&.first
  end

  def current_membership
    return nil unless current_user && current_account

    @current_membership ||= current_user.memberships.find_by(account: current_account)
  end

  def require_user
    if current_user.blank?
      redirect_to new_session_path and return
    elsif current_account.blank?
      reset_session
      redirect_to new_session_path, alert: "当前用户尚未加入任何账号。" and return
    end
  end

  # Bang methods halt the filter chain when used as before_action (via performed?).
  # Explicit return keeps them safe if ever called from an action body.
  def require_role!(*roles)
    allowed = roles.map(&:to_s)
    return if current_membership && allowed.include?(current_membership.role)

    redirect_to root_path, alert: "你没有权限执行此操作。" and return
  end

  def require_editor!
    require_role!(Membership::OWNER, Membership::MARKETER)
  end

  def require_owner!
    require_role!(Membership::OWNER)
  end
end
