# Created by IntelliJ IDEA.
# User: jbroglio
# Date: 2/2/17
# Time: 1:05 PM
# To change this template use File | Settings | File Templates.

class CustomFailure < Devise::FailureApp
  # We override respond to eliminate recall, which causes errors
  def respond
    if http_auth?
      http_auth
    else
      redirect
    end
  end
end