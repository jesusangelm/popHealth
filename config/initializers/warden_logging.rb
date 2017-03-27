Warden::Manager.after_authentication do |user,auth,opts|
  Log.create(:username => user.username, :event => 'login')
end

Warden::Manager.before_failure do |env, opts|
  # We only log failures that have messages associated with them.  This will exclude extra
  # messages appearing where someone tries to access a page before they have logged in.
  unless opts.nil? or opts[:message].nil?
    request = Rack::Request.new(env)
    attempted_login_name = request.params[:user].try(:[], :username) if request.params[:user]
    attempted_login_name = request.params["user"]["username"] if request.params["user"] and request.params["user"]["username"]
    attempted_login_name ||= 'unknown'
    Log.create(:username => attempted_login_name, :event => 'failed login attempt', :description => opts)
  end
end

Warden::Manager.before_logout do |user,auth,opts|
  #this has a chance of getting called with a nil user, in which case we skip logging
  #TODO: figure out why this has a chance of getting called with a nil user (only happens from 403 page)
  if user
    Log.create(:username => user.username, :event => 'logout')
  end
end