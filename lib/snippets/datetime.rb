class Time
  def relative(to_time = Time.now, include_seconds = true, detail = false)
    distance_in_minutes = (((to_time - self).abs)/60).round
    distance_in_seconds = ((to_time - self).abs).round
    case distance_in_minutes
      when 0..1           then time = (distance_in_seconds < 60) ? "#{distance_in_seconds} seconds ago" : '1 minute ago'
      when 2..59          then time = "#{distance_in_minutes} minutes ago"
      when 60..90         then time = "1 hour ago"
      when 90..1440       then time = "#{(distance_in_minutes.to_f / 60.0).round} hours ago"
      when 1440..2160     then time = '1 day ago' # 1-1.5 days
      when 2160..2880     then time = "#{(distance_in_minutes.to_f / 1440.0).round} days ago" # 1.5-2 days
      else time = self.strftime("%a, %d %b %Y")
    end
    return time_stamp(self) if (detail && distance_in_minutes > 2880)
    return time
  end 
end
