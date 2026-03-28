namespace :debug do
  desc "Fetch a Rightmove search page and show what script variables are available"
  task search_page: :environment do
    require "faraday"
    require "nokogiri"

    url = ENV.fetch("URL", "https://www.rightmove.co.uk/property-for-sale/find.html?propertyTypes=terraced%2Csemi-detached&dontShow=newHome%2Cretirement%2CsharedOwnership%2Cauction&channel=BUY&index=0&newHome=false&retirement=false&auction=false&partBuyPartRent=false&sortType=2&areaSizeUnit=sqft&maxPrice=450000&locationIdentifier=USERDEFINEDAREA%5E%7B%22polylines%22%3A%22ia_yHb%7Dg%40%7EFgb%5CcrDw%7E_%40vYc%7EExy%40guChoBor%40%7EaB%3FbmE%60dCvdBlT%7EdCniI%60hEtaB%60GvyPu%7C%40paXuAhmGdg%40%60dCjD%60bDmTrlCajAxtAkxGzrB%7BwEnT%7DyAqpAiwA%7BgL%60O%60%5D%22%7D&transactionType=BUY&displayLocationIdentifier=undefined")

    conn = Faraday.new do |f|
      f.headers["User-Agent"]      = "Mozilla/5.0 (compatible; Bath-Hack-Bot/1.0)"
      f.headers["Accept"]          = "text/html,application/xhtml+xml"
      f.headers["Accept-Language"] = "en-GB,en;q=0.9"
    end

    response = conn.get(url)
    puts "HTTP status: #{response.status}"
    puts "Content-Length: #{response.body.length} bytes\n\n"

    doc = Nokogiri::HTML(response.body)

    puts "=== Script tag variable assignments found ==="
    doc.css("script").each_with_index do |s, i|
      text = s.text
      next if text.strip.empty?
      # Find window.X = or var X = assignments
      matches = text.scan(/(?:window\.(\w+)|var (\w+))\s*=/).flatten.compact.uniq
      next if matches.empty?
      puts "Script #{i}: #{matches.join(', ')} (#{text.length} chars)"
    end

    puts "\n=== Script tags with type=application/json ==="
    doc.css('script[type="application/json"]').each_with_index do |s, i|
      puts "JSON script #{i}: id=#{s['id'].inspect} (#{s.text.length} chars)"
    end

    puts "\n=== __NEXT_DATA__ top-level structure ==="
    next_data_el = doc.at_css('script#__NEXT_DATA__')
    if next_data_el
      data = JSON.parse(next_data_el.text)
      puts JSON.pretty_generate(summarise(data, depth: 3))
    else
      puts "Not found"
    end
  end

  # Recursively summarise a JSON value, replacing long arrays/strings with placeholders
  def summarise(obj, depth:)
    case obj
    when Hash
      return "{ ... #{obj.keys.length} keys }" if depth <= 0
      obj.transform_values { |v| summarise(v, depth: depth - 1) }
    when Array
      return "[... #{obj.length} items]" if depth <= 0 || obj.length > 3
      obj.map { |v| summarise(v, depth: depth - 1) }
    when String
      obj.length > 80 ? "#{obj.first(80)}..." : obj
    else
      obj
    end
  end
end
