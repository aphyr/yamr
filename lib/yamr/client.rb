#!/usr/bin/ruby

class Yamr::Client
  STYLE = File.read(File.join(File.dirname(__FILE__), 'css', 'style.css'))
  POLL_INTERVAL    = 60   # Seconds between checking for new messages
  REFRESH_INTERVAL = 5000 # ms between refreshing display
  BROWSER_CMD      = 'chromium-browser'
  CONFIG_FILE      = File.join(ENV['HOME'], '.config', 'yamr', 'config')

  include Yamr::CGI

  def initialize
    @messages = []
  end

  # Sets up OAUTH
  def auth
    if token = @config.oauth.token and secret = @config.oauth.secret
      # Use cached credentials
      @y = Yammer::Client.new(
        :consumer => {
          :key => Yamr::OAUTH_APP_KEY,
          :secret => Yamr::OAUTH_APP_SECRET
        },
        :access => {
          :token => token,
          :secret => secret
        }
      )
      return true
    end 

    # Go through the whole rigamarole...
    consumer = OAuth::Consumer.new(
      Yamr::OAUTH_APP_KEY,
      Yamr::OAUTH_APP_SECRET,
      {:site => "https://www.yammer.com"}
    )

    # Get request token
    request_token = consumer.get_request_token
    fork { exec BROWSER_CMD, request_token.authorize_url }

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

    win.show_all
  end

  # Sets up the yammer client based on an OAUTH access token. Saves the given
  # token info in the config.
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

    # Save token and secret for next time
    @config.oauth.token = access_token.token
    @config.oauth.secret = access_token.secret
    save

    # Grab initial messages
    fetch_messages
  end
 
  # The current Yammer user
  def current_user
    @current_user ||= @y.current_user
  end

  # Deletes a message ID
  def delete(id)
    @y.message(:delete, :id => id)
    @messages.delete_if do |msg|
      msg.id == id
    end
    render_messages
  end

  # Gets messages from the API.
  # Calls notify(messages) if @messages is not empty.
  def fetch_messages()
    return false unless @y
    begin
      messages = @y.messages(:all, :newer_than => @last_id).reverse
      unless messages.empty?
        notify messages unless @messages.empty?
        @messages += messages
        @last_id = messages.last.id
      end
    rescue => e
      puts "Error fetching new messages: #{e.inspect}"
    end
  end

  # Load configuration
  def load
    @config = begin
      Construct.load(File.read(CONFIG_FILE))
    rescue
      Construct.new
    end

    @config.define :oauth, :default => Construct.new
    @config.oauth.define :token, :default => nil
    @config.oauth.define :secret, :default => nil
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
    str = escape_html str
    @y.message(:post, :body => str)
  end

  # Quit the app
  def quit
    Gtk.main_quit
  end

  # Get messages, set up recurring functions...
  def run
    # Get initial messages and display right away.
    fetch_messages
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

  # Saves configuration
  def save
    FileUtils.mkdir_p File.dirname(CONFIG_FILE)
    File.open(CONFIG_FILE, 'w') do |f|
     f.write @config.to_yaml
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
      html << '<div class="text">'
      html << '<h1 class="user">'
      html << "<a target=\"_blank\" href=\"#{message.web_url}\">#{user.full_name}</a>"
      html << '</h1>'
      # TODO: rewrite yammer4r ==
      if user.name == current_user.name
        html << "<a class=\"delete\" href=\"yamr://delete/#{message.id}\">x</a>"
      end
      html << '<div class="body">' + body + '</div>'
      html << '<div class="date">' + date.relative + '</div>'
      html << '<div class="visual-clear"></div>'
      html << '</div>'
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
    row = Gtk::HBox.new
    @stack.pack_start row, false

    # Text field
    message_entry = Gtk::Entry.new
    message_entry.signal_connect('activate') do
      text = message_entry.text
      message_entry.text = ''
      post text
    end
    row.pack_start message_entry, true

    # Button
    button = Gtk::Button.new 'Yamr!'
    button.signal_connect 'clicked' do
      text = message_entry.text
      message_entry.text = ''
      post text
    end
    row.pack_start button, false

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
      fork { exec(BROWSER_CMD, request.uri) }
      true
    end

    # Handle function calls
    @view.signal_connect 'navigation-policy-decision-requested' do |view, frame, request, navigation_action, policy_decision, user_data|
      if request.uri[/^yamr:\/\/(.+)$/]
        yamr_uri $1
        true
      end
    end

    @window.show_all
  end
  
  def start
    Gtk.init
    self.load
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

  # Handles YAMR URI callbacks from the browser.
  def yamr_uri(uri)
    fragments = uri.split('/')
    case fragments.shift
    when 'delete'
      # Delete a post.
      id = fragments.shift.to_i
      message = @messages.find { |m| m.id == id }
      p message
      dialog = Gtk::MessageDialog.new(
        @window, 
        Gtk::Dialog::MODAL | Gtk::Dialog::DESTROY_WITH_PARENT,
        Gtk::MessageDialog::QUESTION,
        Gtk::MessageDialog::BUTTONS_YES_NO, 
        "Are you sure you want to delete this message?"
      )
      dialog.secondary_text = message.body.parsed

      dialog.signal_connect 'response' do |dialog, response|
        if response == -8 # Not Gtk::Dialog::RESPONSE_OK?
          delete id
        end
      end

      dialog.run
      dialog.destroy
    else
      puts "Unknown YAMR uri #{uri}"
    end
  end
end
