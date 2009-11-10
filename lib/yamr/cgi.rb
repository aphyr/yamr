module Yamr::CGI
  # Little functions for text processing--mostly stolen from Rack

  # Escape ampersands, brackets and quotes to their HTML/XML entities.
  def escape_html(string)
    string.to_s.gsub("&", "&amp;").
      gsub("<", "&lt;").
      gsub(">", "&gt;").
      gsub("'", "&#39;").
      gsub('"', "&quot;")
  end

  # Unescapes a URI escaped string. (Stolen from Camping).
  def unescape(s)
    s.tr('+', ' ').gsub(/((?:%[0-9a-fA-F]{2})+)/n){
      [$1.delete('%')].pack('H*')
    }
  end
  
  # Performs URI escaping so that you can construct proper
  # query strings faster.  Use this rather than the cgi.rb
  # version since it's faster.  (Stolen from Camping).
  def escape(s)
    s.to_s.gsub(/([^ a-zA-Z0-9_.-]+)/n) {
      '%'+$1.unpack('H2'*bytesize($1)).join('%').upcase
    }.tr(' ', '+')
  end
end
