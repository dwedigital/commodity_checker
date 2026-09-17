# frozen_string_literal: true

# Account settings.
#
# Google owns the email address and the credential, so there is nothing to edit
# here. What remains is seeing which Google account is linked and being able to
# close the account, which the old Devise registration edit page carried.
class Users::AccountsController < ApplicationController
  before_action :authenticate_user!

  def show
    @user = current_user
  end

  def destroy
    user = current_user
    sign_out(:user)
    user.destroy!

    redirect_to root_path, notice: "Your account and all its data have been deleted."
  end
end
