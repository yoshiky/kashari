require 'rubygems'
require 'sinatra'
require 'sinatra/reloader' if development?
require 'instagram'
require 'yaml'
require 'haml'

enable :sessions

configure :development do
  config = YAML::load_file('config.yml')
  Instagram.configure do |conf|
    conf.client_id     = config['instagram']['client_id']
    conf.client_secret = config['instagram']['client_secret']
  end
end

configure :production do
  Instagram.configure do |conf|
    conf.client_id     = ENV['INSTAGRAM_CLIENT_ID']
    conf.client_secret = ENV['INSTAGRAM_CLIENT_SECRET']
  end
end

helpers do
  def base_url
    "#{request.scheme}://#{request.host}#{':' + request.port.to_s if request.port != 80}/"
  end

  def callback_url
    base_url + 'oauth/callback'
  end

  def subscript_url
    base_url + '/subscription/callback'
  end
end

get '/' do
  haml :index
end

get '/oauth/connect' do
  redirect Instagram.authorize_url(:redirect_uri => callback_url)
end

get '/oauth/callback' do
  response = Instagram.get_access_token(params[:code], :redirect_uri => callback_url)
  session[:access_token] = response.access_token
  redirect '/feed'
end

get '/feed' do
  client = Instagram.client(:access_token => session[:access_token])
  @user = client.user

  @images = []
  for media_item in client.user_recent_media
    @images << media_item.images.thumbnail.url
  end
  haml :feed
end

get '/location_search' do
  client = Instagram.client(:access_token => session[:access_token])
  location_id = 1234
  recent_medias = client.location_recent_media(location_id)
  html = "<h1>Media Location ID #{location_id} </h1>"
  for media_item in recent_medias
    html << "<img src='#{media_item.images.thumbnail.url}'>"
    html << "<p>#{media_item.caption.text unless media_item.caption.nil?}</p>"
    html << "<p>UserName: #{media_item.caption.from.username unless media_item.caption.nil? }</p>"
  end
  html
end

get '/location' do
  lat = "35.681518158082845"
  lng = "139.7708559036255"
  location = Instagram.location_search(lat, lng, :count => 1).first
  medias = Instagram.location_recent_media(location.id)
  media = medias.first
  html = "<h1>Media Location ID #{location.id} </h1>"
  html << "<ul>"
  medias.each{|media|
    html << "<li><img src=\'#{media.images.low_resolution.url}\'></li>"
  }
  html << "</ul>"
  html
end

# 購読リクエスト
post '/subscription' do
  client = Instagram.client(:access_token => session[:access_token])
  
  # Shibuya
  lat    = '35.657872'
  lng    = '139.70232'
  radius = 1000 
  obj = client.create_subscription(:client_id     => Instagram.options['client_id'],
                                   :client_secret => Instagram.options['client_secret'],
                                   :object        => 'geography',
                                   :aspect        => 'media',
                                   :lat           => lat,
                                   :lng           => lng,
                                   :radius        => radius,
                                   :callback_url  => subscript_url)
  obj
end

# Instagramからのcallback先
get '/subscription/callback' do
  params[:'hub.challenge']
end

# Instagramからリアルタイム購読を受ける
post '/subscription/callback' do
  puts "###request#################"
  puts "#{request.body}"
  puts "#{params[:body].inspect}"
  puts "####################"

  Instagram.process_subscription(response.body.read) do |handler|
    handler.on_geography_changed do |object_id|
      data = Instagram.geography_recent_media(object_id)
    end
  end
  puts "####################"
  puts "#{data.inspect}"
  puts "####################"
  200
end

# 購読停止
delete '/subscription' do
  client = Instagram.client(:access_token => session[:access_token])
  client.delete_subscription(:object=>"all")
  200
  redirect '/'
end
