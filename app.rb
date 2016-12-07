require 'rubygems'
require 'bundler/setup'
require 'sinatra'
require 'sinatra/config_file'
require 'recaptcha'
require 'fileutils'
require 'data_mapper'

enable :sessions

# Create config.yaml in the app root. You can do this by renaming the
# config.yaml.sample file and updating the default values
config_file "#{Dir.pwd}/config.yaml"

# Configure the Recaptca plugin
Recaptcha.configure do |config|
  config.site_key = settings.site_key
  config.secret_key = settings.secret_key
end

include Recaptcha::ClientHelper
include Recaptcha::Verify

class Student
  include DataMapper::Resource

  property :netid      , String , :key => true
  property :password   , BCryptHash

  belongs_to :section
end

class Section
  include DataMapper::Resource

  property :name, String, :key => true
  
  has n, :students
end

DataMapper.finalize

PUBLICDIR = File.join(Dir.pwd, 'public', 'student')

configure do

  # DBURL is defined in the config.yaml file
  DataMapper.setup(:default, settings.database_url || "sqlite3://#{Dir.pwd}/demo.db")

  DataMapper.auto_upgrade!

  # uncomment to modify the schema
  #DataMapper.auto_migrate!

  # Data Mapper fails silently returning true. Uncomment this to raise errors
  # instead. Good for initial debugging.
  DataMapper::Model.raise_on_save_failure = true

  begin
    #create the DEFAULT section if it does not exist
    Section.first_or_create(:name => settings.default_section)

    # create admin user if it does not exist
    Student.first_or_create( { :netid => 'admin'} , {:password => settings.admin_password, :section_name => settings.default_section} )

  rescue DataMapper::SaveFailureError => e
    puts e.resource.errors.inspect
  end

end


get '/' do
  redirect '/me' if session[:netid] != nil
  erb :main
end

get '/register' do
  erb :register
end


post '/register' do


  # Check the CAPTCHA
  if verify_recaptcha

    # Make sure passwords match
    if params['password'] == params['password2']
      
      # Check if section exists
      section = Section.get(params[:section_name])
      if section != nil

        netid = params[:netid]
        studentdir = File.join(PUBLICDIR, netid)

        # Check if the username is already taken
        user = Student.get(netid)
        if user == nil and not Dir.exist?(studentdir)
          begin

            # Create a new record in the db
            user = Student.new()
            user.netid = netid
            user.password = params[:password]
            user.section_name = params[:section_name]
            user.save

            # Crete directory
            Dir.mkdir(studentdir)
            Dir.mkdir(File.join(studentdir, 'lab8'))
            Dir.mkdir(File.join(studentdir, 'lab9'))
            Dir.mkdir(File.join(studentdir, 'project'))

            # log the user in
            session[:netid] = netid

            redirect '/me'

          rescue DataMapper::SaveFailureError => e
            puts e.resource.errors.inspect
            @message = "Database Error Has Occurred."
            erb :error
          end

        else
          @message = "Username already taken. Please pick a different one."
          erb :error
        end

      else
        @message = "Invalid section number. Please try again."
        erb :error
      end

    else
      @message = "The passwords you entered do not match. Please try again."
      erb :error
    end
  else
    @message = "You have failed the CAPTCHA. Are you sure you're not a robot?"
    erb :error
  end
end


get '/password' do
  redirect '/login' if session[:netid] == nil
  erb :password
end

post '/password' do

    if params['password'] == params['password2']

      if session[:netid] == 'admin' and params['for']
        username = params['for']
      else
        username = session[:netid]
      end

      begin
        student = Student.get(username)
        student.password = params['password']
        student.save
        redirect '/me'
      rescue DataMapper::SaveFailureError => e
        puts e.resource.errors.inspect
        @message = "Database Error Has Occurred."
        erb :error
      end
    else
      @message = "The passwords you entered do not match. Please try again."
      erb :error
    end
end


get '/me' do
  redirect '/login' if session[:netid] == nil
  redirect '/admin' if session[:netid] == 'admin'

  Project = Struct.new(:name, :stub, :files)

  @netid = session[:netid]
  @link = settings.url + "/student/#{session[:netid]}"

  lab8     = File.join(PUBLICDIR, @netid, 'lab8', '*')
  lab9     = File.join(PUBLICDIR, @netid, 'lab9', '*')
  project  = File.join(PUBLICDIR, @netid, 'project', '*')
  
  @project = [
                Project.new('Lab 8', 'lab8', Dir.glob(lab8)),
                Project.new('Lab 9', 'lab9', Dir.glob(lab9)),
                Project.new('Project', 'project', Dir.glob(project))
  ]

  erb :me 
end



get '/login' do
  erb :login
end

post '/login' do
  redirect '/me' if session[:netid] != nil

  student = Student.get(params[:netid])

  if student != nil and student.password == params[:password] and verify_recaptcha
    session[:netid] = params[:netid]
    redirect '/me'
  else
    redirect '/login'
  end

end

get '/logout' do
  session[:netid] = nil
  redirect '/'
end



get '/upload/:project' do

  redirect '/login' if session[:netid] == nil

  @project = params['project']

  if @project == 'lab8' || @project == 'lab9' || @project == 'project'

    erb :upload
    
  else
    @message = "The name <samp>#{@project}</samp> is not a valid assignment name."
    erb :error
  end
end

post '/upload/:project' do

  redirect '/login' if session[:netid] == nil

  @netid = session[:netid]
  @project = params['project']

  if @project == 'lab8' || @project == 'lab9' || @project == 'project'

    if params['inputfile']

      dir = File.join(PUBLICDIR, @netid, @project)
      filename = params['inputfile'][:filename]
      tempfile = params['inputfile'][:tempfile]

      File.open(File.join(dir, filename), 'wb') do |f|
        f.write tempfile.read
      end

      redirect '/me'


    else
      @message = "No file chosen. Please choose a file to upload."
      erb :error
    end

  else
    @message = "The name <samp>#{@assignment}</samp> is not a valid assignment name."
    erb :error
  end

end

get '/delete/:project/:file' do

  redirect '/login' if session[:netid] == nil

  netid = session[:netid]
  project = params['project']
  file = params['file']

  filename = File.join(PUBLICDIR, netid, project, file)
  File.delete(filename)
  redirect '/me'  

end


get '/admin' do

  redirect '/login' if session[:netid] == nil
  redirect '/me' if session[:netid] != 'admin'

  @sections = Section.all()
  erb :admin
end


get '/admin/section/view/:section' do

  redirect '/login' if session[:netid] == nil
  redirect '/me' if session[:netid] != 'admin'


  @admin = true
  @dir = PUBLICDIR
  @section = params[:section]
  @students = Student.all(:section_name => @section)
  erb :section
end


get '/admin/student/view/:name' do

  redirect '/login' if session[:netid] == nil
  redirect '/me' if session[:netid] != 'admin'

  Project = Struct.new(:name, :stub, :files)

  @admin = true
  @netid = params[:name]
  @link = settings.url + "/student/#{@netid}"

  lab8     = File.join(PUBLICDIR, @netid, 'lab8', '*')
  lab9     = File.join(PUBLICDIR, @netid, 'lab9', '*')
  project  = File.join(PUBLICDIR, @netid, 'project', '*')
  
  @project = [
                Project.new('Lab 8', 'lab8', Dir.glob(lab8)),
                Project.new('Lab 9', 'lab9', Dir.glob(lab9)),
                Project.new('Project', 'project', Dir.glob(project))
  ]

  erb :me 
end

get '/admin/student/reset/:name' do
  redirect '/login' if session[:netid] == nil
  redirect '/me' if session[:netid] != 'admin'

  @admin = true
  @for = params[:name]
  erb :password
end


get '/admin/section/new' do
  redirect '/login' if session[:netid] == nil
  redirect '/me' if session[:netid] != 'admin'
  erb :newsection
end


post '/admin/section/new' do
  redirect '/login' if session[:netid] == nil
  redirect '/me' if session[:netid] != 'admin'

  name = params['section_name']

  if Section.get(name)
    @message = "Section #{name} already exists."
    erb :error
  else

    begin
      section = Section.new()
      section.name = name
      section.save
      redirect '/me'
    rescue DataMapper::SaveFailureError => e
      puts e.resource.errors.inspect
      @message = "Database Error Has Occurred."
      erb :error
    end

  end
end


get '/admin/section/delete/:name' do
  redirect '/login' if session[:netid] == nil
  redirect '/me' if session[:netid] != 'admin'

  @what = 'section'
  @name = params[:name]
  erb :delete

end


get '/admin/student/delete/:name' do
  redirect '/login' if session[:netid] == nil
  redirect '/me' if session[:netid] != 'admin'

  @what = 'student'
  @name = params[:name]
  erb :delete
end

post '/admin/student/delete' do
  redirect '/login' if session[:netid] == nil
  redirect '/me' if session[:netid] != 'admin'

  if params['confirmation'] == 'DELETE'

    name = params['object']
    folder = File.join(PUBLICDIR, name)

    if name == 'admin'
      @message = "Can't delete admin user."
      halt erb(:error)
    end

    begin
      student = Student.get(name)
      student.destroy

      FileUtils.rm_rf(folder)
      redirect '/me'

    rescue DataMapper::SaveFailureError => e
      puts e.resource.errors.inspect
      @message = "Database Error Has Occurred."
      erb :error
    end

  else
    @message = "No confirmation. Please try again."
    erb :error
  end
end

post '/admin/section/delete' do
  redirect '/login' if session[:netid] == nil
  redirect '/me' if session[:netid] != 'admin'

  if params['confirmation'] == 'DELETE'

    section = params['object']

    if section == settings.default_section
      @message = "Can't delete the default section."
      halt erb(:error)
    end

    students = Student.all(:section_name => section)

    students.each do |student|

      unless student.netid == 'admin'

        name = student.netid
        folder = File.join(PUBLICDIR, name)

        begin
          student = Student.get(name)
          student.destroy
          FileUtils.rm_rf(folder)

        rescue DataMapper::SaveFailureError => e
          puts e.resource.errors.inspect
          @message = "Database Error Has Occurred."
          erb :error
        end
      end

    end

    sec = Section.get(section)
    sec.destroy
    
    redirect '/me'

  else
    @message = "No confirmation. Please try again."
    erb :error
  end
end
