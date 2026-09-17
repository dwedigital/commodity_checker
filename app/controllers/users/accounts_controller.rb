# frozen_string_literal: true

# Account settings.
#
# Shows how the account signs in, lets someone set or change a password, and
# lets them close the account.
class Users::AccountsController < ApplicationController
  before_action :authenticate_user!

  def show
    @user = current_user
  end

  # Setting the first password on a Google account, or changing an existing one.
  #
  # Changing a password requires the current one. Setting a first password does
  # not, because there is nothing to prove — the session itself is the proof,
  # and it was created by Google.
  def update_password
    @user = current_user
    had_password = @user.password_set?

    if had_password && !@user.valid_password?(params.dig(:user, :current_password).to_s)
      @user.errors.add(:current_password, "is not correct")
      return render :show, status: :unprocessable_entity
    end

    if @user.update(password_params)
      # Changing the password rotates the session, so sign back in.
      bypass_sign_in(@user)
      redirect_to account_path,
                  notice: had_password ? "Your password has been changed." : "Your password has been set. You can now sign in with your email address or with Google."
    else
      render :show, status: :unprocessable_entity
    end
  end

  def destroy
    user = current_user
    sign_out(:user)
    user.destroy!

    redirect_to root_path, notice: "Your account and all its data have been deleted."
  end

  private

  def password_params
    params.require(:user).permit(:password, :password_confirmation)
  end
end
