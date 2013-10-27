require 'json'
require 'time'

require 'sinatra'
require 'sinatra/cookies'
require 'ripple'
require 'pony'

require './texts'

class ModuleModel # Cause calling it Module fucks up the whole of Ruby
  include Ripple::Document
  property :name, String
  property :code, String

  many :deadlines, :class_name => "Deadline"
end

class Deadline
  include Ripple::Document
  property :name, String
  property :due, Time

  one :module, :class_name => "ModuleModel"
end

class User
  include Ripple::Document
  property :name, String
  property :password, String
  property :email, String
  property :number, String
  property :session, String

  many :modules, :class_name => "ModuleModel"
end

configure do
  Ripple.load_config('./config/ripple.yml', ['development'])
  set :cookie_options, {:httponly => false }
end

before do
  if cookies[:session_key]
    User.all.each do |user|
      @user = user if user.session == cookies[:session_key]
    end
  end
end

helpers do
  def send_user(user)
    mods = []
    user.modules.each do |mod|
      mods << mod.serializable_hash
    end
    user.serializable_hash.merge({ :modules => mods }).to_json
  end
end

get '/' do
  redirect '/index.html'
end

post '/users' do
  content_type "application/json"

  params = JSON.parse(request.body.read)
  unless params['name'] and params['password']
    status 400
    halt ({ :error => 'Must specify deadline name and password' }).to_json
  end

  user = User.new
  user.name = params['name']
  user.password = params['password']
  user.email = params['email'] if params['email']
  user.number = params['number'] if params['number']
  user.session = (0...50).map{ ('a'..'z').to_a[rand(26)] }.join
  user.save

  cookies[:session_key] = user.session
  user.to_json
end

post '/users/add_module/:id' do
  if not @user
    status 401
    halt "Must be logged in"
  end

  content_type "application/json"

  mod = ModuleModel.find(params['id'])
  puts mod
  @user.modules << mod
  @user.save
  puts @user

  send_user(@user)
end


post '/login' do
  content_type "application/json"

  if @user
    halt send_user(@user)
  end

  params = JSON.parse(request.body.read)
  unless params['email'] and params['password']
    status 401
    halt ({ :error => "Needs username and password"}).to_json
  end

  user = nil
  User.all.each do |u|
    user = u if u.email == params['email']
  end
  if user.nil?
    raise Sinatra::NotFound
  end

  unless user.password == params['password']
    status 400
    halt ({ :error => "Worng username or password"}).to_json
  end

  user.session = (0...50).map{ ('a'..'z').to_a[rand(26)] }.join
  cookies[:session_key] = user.session
  user.save

  user.to_json
end

get '/deadlines' do
  content_type "application/json"
  deadlines_hash = []
  if @user
    @user.modules.each do |mod|
      mod.deadlines.each do |d|
        deadlines_hash << d.serializable_hash.merge({ :module => d.module.serializable_hash })
      end
    end
  else
    Deadline.all.each do |deadline|
      deadlines_hash << deadline.serializable_hash.merge({ :module => deadline.module.serializable_hash })
    end
  end
  deadlines_hash.to_json
end

get '/deadlines/:id' do
  content_type "application/json"
  deadline = Deadline.find(params['id'])
  if deadline.nil?
    raise Sinatra::NotFound
  else
    deadline.serializable_hash.merge({ :module => deadline.module.serializable_hash }).to_json
  end
end

post '/deadlines' do
  content_type "application/json"

  params = JSON.parse(request.body.read)
  unless params['name'] and params['due'] and params['module']
    status 400
    halt ({ :error => 'Must specify deadline name, due date and module' }).to_json
  end

  deadline = Deadline.new
  mod = ModuleModel.find(params['module'])
  deadline.name = params['name']
  deadline.due = Time.parse(params['due'])
  deadline.module = mod
  deadline.save
  mod.deadlines << deadline
  mod.save

  if @user and @user.number
    send_text(@user.number, @user.name, deadline.name, deadline.due.to_s)
  end

  if @user and @user.email
    body = "Hey #{@user.name}, just to remind you, #{deadline.name} is due #{deadline.due}"
    Pony.mail(:to => @user.email, :from => 'dom@crevent.co', :subject => 'Reminder', :body => body)
  end

  deadline.to_json
end

get '/modules' do
  content_type "application/json"

  mods = []
  ModuleModel.all.each do |mod|
    mods << mod.serializable_hash.merge({ :deadlines => mod.deadlines })
  end
  mods.to_json
end

get '/modules/:id' do
  content_type "application/json"
  mod = ModuleModel.find(params['id'])
  if mod.nil?
    raise Sinatra::NotFound
  else
    mod.to_json
  end
end

post '/modules' do
  content_type "application/json"

  params = JSON.parse(request.body.read)
  unless params['name'] or params['code']
    status 400
    halt ({ :error => 'Must specify module name or code' }).to_json
  end

  mod = ModuleModel.new
  mod.name = params['name'] if params['name']
  mod.code = params['code'] if params['code']
  mod.save
  mod.to_json
end

delete '/modules/:id' do
  ModuleModel.find(params['id']).destroy
  "OK"
end

not_found do
  'Not found'
end
