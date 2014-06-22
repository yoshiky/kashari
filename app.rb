require 'sinatra/reloader' if development?
require 'json'
require 'yaml'

enable :sessions 
set :session_secret, 'tripwindow'
CONFIG = YAML::load_file('config.yml') if development?

configure :development do
  Instagram.configure do |conf|
    conf.client_id     = CONFIG['instagram']['client_id']
    conf.client_secret = CONFIG['instagram']['client_secret']
  end
  REDIS = Redis.new
end

configure :production do
  Instagram.configure do |conf|
    conf.client_id     = ENV['INSTAGRAM_CLIENT_ID']
    conf.client_secret = ENV['INSTAGRAM_CLIENT_SECRET']
  end
  uri = URI.parse(ENV['REDISTOGO_URL'])
  REDIS = Redis.new(:host => uri.host, :port => uri.port, :password => uri.password)
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

get '/admin' do
  redirect '/oauth/connect'
end

get '/oauth/connect' do
  redirect Instagram.authorize_url(:redirect_uri => callback_url)
end

get '/oauth/callback' do
  response = Instagram.get_access_token(params[:code], :redirect_uri => callback_url)
  session[:access_token] = response.access_token
  redirect '/feed'
end

# 購読リクエスト
# Command to Create a Subscription
# ex)
# curl -F 'client_id=CLIENT-ID' \
#      -F 'client_secret=CLIENT-SECRET' \
#      -F 'object=geography' \
#      -F 'aspect=media' \
#      -F 'lat=35.659084' \
#      -F 'lng=139.701017' \
#      -F 'radius=1000' \
#      -F 'callback_url=http://tripwindow.herokuapp.com/subscription/callback' \
#      https://api.instagram.com/v1/subscriptions/
#
post '/subscription' do
  client = Instagram.client(:access_token => session[:access_token])
  
  # Shibuya
  lat    = '35.659084'
  lng    = '139.701017'
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
  Instagram.process_subscription(request.body.read) do |handler|
    handler.on_geography_changed do |object_id|
      photos = Instagram.geography_recent_media(object_id)
      photos.each do |photo|
        text = photo.caption.nil? ? "" : photo.caption.text
        photo_data = {:id => photo.id,
                      :url => photo.images.low_resolution.url,
                      :text => text,
                      :link => photo.link,
                      :created_time => photo.created_time}
        #REDIS.lpush("photo_data", photo_data.to_json)
        REDIS.zadd("sorted_photos", photo.id.split("_")[0], photo_data.to_json)
      end
      #REDIS.ltrim "photo_data", 0, 19
      REDIS.zremrangebyrank "sorted_photos", 100, -1
    end
  end
  200
end

# 購読停止
delete '/subscription' do
  client = Instagram.client(:access_token => session[:access_token])
  client.delete_subscription(:object=>"all")
  200
  redirect '/'
end

# view
get '/' do
  #@photos = REDIS.lrange("photo_data", 0, 19)
  @photos = REDIS.zrevrange("sorted_photos", 0, 99)
  haml :index
end

# TODO 消す or 何かに再利用
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

get '/test' do
  num = rand(3)
  puts lat = CONFIG['geography'][num]['lat']
  puts lng = CONFIG['geography'][num]['lng']
end
