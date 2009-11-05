#!/usr/bin/ruby

class Yamr::Client
  STYLE = File.read(File.join(File.dirname(__FILE__), 'css', 'style.css'))
  POLL_INTERVAL    = 60   # Seconds between checking for new messages
  REFRESH_INTERVAL = 5000 # ms between refreshing display
  BROWSER_CMD      = 'chromium-browser'

  def initialize
    @config_path = File.join(ENV['HOME'], '.yammer.yaml')
    @messages = []
  end

  # Sets up OAUTH
  def auth
    consumer = OAuth::Consumer.new(
      Yamr::OAUTH_APP_KEY,
      Yamr::OAUTH_APP_SECRET,
      {:site => "https://www.yammer.com"}
    )

    # Get request token
    request_token = consumer.get_request_token
    system BROWSER_CMD, request_token.authorize_url
    puts "here"

    # Accept the code
    win = Gtk::Window.new
    win.window_position = Gtk::Window::POS_CENTER 
    win.title = "#{Yamr::NAME} #{Yamr::VERSION} - OAUTH Verification"

    row = Gtk::HBox.new
    win.add row
    
    # Entry field
    code = nil
    entry = Gtk::Entry.new
    entry.signal_connect 'activate' do
      code = entry.text.strip
      connect request_token.get_access_token(:oauth_verifier => code)
      win.destroy
    end
    row.pack_start entry

    # Entry button
    button = Gtk::Button.new 'Authorize'
    button.signal_connect 'clicked' do
      code = entry.text.strip
      connect request_token.get_access_token(:oauth_verifier => code)
      win.destroy
    end
    row.pack_start button, false

    # Wait for the code
    win.show_all
  end

  # Sets up the yammer client based on an OAUTH access token.
  def connect(access_token)
    @y = Yammer::Client.new(
      :consumer => {
        :key => Yamr::OAUTH_APP_KEY, 
        :secret => Yamr::OAUTH_APP_SECRET
      },
      :access => { 
        :token => access_token.token,
        :secret => access_token.secret
      }
    )
    fetch_messages
  end
  
  # Gets messages from the API and notifies if necessary
  def fetch_messages(notify = true)
    return false unless @y
    begin
      messages = @y.messages(:all, :newer_than => @last_id).reverse
      unless messages.empty?
        @messages += messages
        notify messages if notify
        @last_id = messages.last.id
      end
    rescue => e
      puts "Error fetching new messages: #{e.inspect}"
    end
  end

  # Alert the user to new messages
  def notify(messages)
    messages.each do |message|
      date = DateTime.parse(message.created_at)
      user = users[message.sender_id] || users(true)[message.sender_id]

      system("notify-send", '-i', 'gtk-dialog-info', '-t', '10000', user.full_name, message.body.parsed)
    end
  end

  # Post an update
  def post(str)
    @y.message(:post, :body => str)
  end

  # Quit the app
  def quit
    Gtk.main_quit
    exit 0
  end

  # Get messages, set up recurring functions...
  def run
    # Get initial messages and display right away.
    fetch_messages false
    render_messages

    # Every so often, scan for new messages
    Gtk.timeout_add(POLL_INTERVAL * 1000) do
      fetch_messages
      true
    end

    # Refresh the display
    Gtk.timeout_add(REFRESH_INTERVAL) do
      render_messages
    end
  end

  # Force the background color of a widget.
  def force_bg(widget, color)
    color = Gdk::Color.parse color
    [Gtk::STATE_NORMAL, Gtk::STATE_ACTIVE, Gtk::STATE_PRELIGHT, Gtk::STATE_SELECTED, Gtk::STATE_INSENSITIVE].each do |state|
       widget.modify_bg state, color
    end
  end

  def render_messages
    style = File.read(File.join(File.dirname(__FILE__), 'css', 'style.css'))
    html = "<html><head><style type=\"text/css\">#{style}</style></head><body>"
    html << '<div class="messages">'
    
    @messages.reverse.each do |message|
      # Padding
      # Set up some of the data we'll need from the message
      date = Time.parse(message.created_at)
      user = users[message.sender_id] || users(true)[message.sender_id]
      body = message.body.parsed

      # Write the message
      html << '<div class="message">'
      html << "<img class=\"mugshot\" src=\"#{user.mugshot_url}\" alt=\"#{user.name}\" />"
      html << '<h1 class="user">'
      html << "<a target=\"_blank\" href=\"#{message.web_url}\">#{user.full_name}</a>"
      html << '</h1>'
      html << '<div class="body">' + body + '</div>'
      html << '<div class="date">' + date.relative + '</div>'
      html << '<div class="visual-clear"></div>'
      html << '</div>'
    end

    html << '</div>'
    html << '</body></html>'
    
    # Ask Gtk to reload the view...
    Gtk.queue do
      @pos = @messages_container.vadjustment.value
      @view.load_html_string html
      true
    end
  end

  def setup
    # Create window
    @window = Gtk::Window.new
    @window.title = "#{Yamr::NAME} #{Yamr::VERSION}"
    @window.set_default_size 300, 800
    
    # Exit on close
    @window.signal_connect('destroy') do
      quit
    end

    # Messages column
    @stack = Gtk::VBox.new
    @window.add @stack
   
    # Update entry area
    @message_entry = Gtk::Entry.new
    @message_entry.signal_connect('activate') do
      post @message_entry.text
    end
    @stack.pack_start @message_entry, false

    # Messages area
    @messages_container = Gtk::ScrolledWindow.new
    @messages_container.set_policy Gtk::POLICY_NEVER, Gtk::POLICY_AUTOMATIC
    @stack.pack_start @messages_container

    @view = Gtk::WebKit::WebView.new
    @messages_container.add @view
    
    # Rescroll on reload
    @view.signal_connect 'load-finished' do
      @messages_container.vadjustment.value = @pos
    end

    # Open links in the browser
    @view.signal_connect 'new-window-policy-decision-requested' do |view, frame, request, nav_action, policy_decision, user_data|
      system(BROWSER_CMD, request.uri)
      true
    end

    @window.show_all
  end
  
  def start
    Gtk.init
    setup
    auth
    run
    Gtk.main_with_queue 100
  end

  def users(fetch = false)
    if fetch or @users.nil?
      @users = Hash[*@y.users.map { |u| [u.id, u] }.flatten]
    else
      @users
    end
  end
end
