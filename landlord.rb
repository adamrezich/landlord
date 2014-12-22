#!/usr/bin/env ruby

require 'rubygems'
require 'mechanize'
require 'colorize'
require 'json'

failed = false

def get_avalon
  
  unless $cfg['logins'].key?('avalon') or $cfg['logins']['avalon'].key?('username') or $cfg['logins']['avalon'].key?('password')
    raise 'error reading Avalon configuration'
  end

  rent = 0.0
  sewage = 0.0
  garbage = 0.0
  unpaid = 0.0

  a = Mechanize.new { |agent|
    agent.user_agent_alias = 'Mac Safari'
  }

  begin
    a.get('https://www.avalonaccess.com/UserProfile/LogOn') do |page|
      page = page.form_with(:action => '/UserProfile/LogOn') do |f|
        f.UserName = $cfg['logins']['avalon']['username']
        f.password = $cfg['logins']['avalon']['password']
      end.click_button

      puts 'Logged into Avalon Access successfully'.blue
      
      ledger_timestamp = 0
      a.get('https://www.avalonaccess.com/Payment/OneTimePayment') do |payment|
        ledger_timestamp = payment.at('#ledgerTimestamp')['value']
      end

      #puts page.at('#current-balance').text.strip
      #ledger_timestamp = page.at('#ledgerTimestamp')['value']
      #ledger_timestamp = '0'
      unix_timestamp = (Time.now.to_f * 1000).to_i

      puts 'ledger: ' + ledger_timestamp
      #puts 'unix: '   + unix_timestamp.to_s

      #balance_url = "https://www.avalonaccess.com/Dashboard/CurrentBalanceDetails?ledgerTimestamp=#{ledger_timestamp}&_=#{unix_timestamp}"
      payment_url = "https://www.avalonaccess.com/Payment/BalanceDetails?ledgerTimestamp=#{ledger_timestamp}&_=#{unix_timestamp}"

      a.get(payment_url) do |payment|
        #puts 'PAYMENT:'
        #puts payment.body
        sewage = payment.at('td:contains("Sewer Charge")').next_element.next_element.text.strip.gsub(/[\$,]/, '').to_f or 0.0
        sewage += payment.at('td:contains("Utility service fee")').next_element.next_element.text.strip.gsub(/[\$,]/, '').to_f or 0.0
        sewage += payment.at('td:contains("Water Submetering Reim.")').next_element.next_element.text.strip.gsub(/[\$,]/, '').to_f or 0.0
        garbage = payment.at('td:contains("Trash Collections")').next_element.next_element.text.strip.gsub(/[\$,]/, '').to_f or 0.0
        rent = payment.at('td:contains("Rent Receivable")').next_element.next_element.text.strip.gsub(/[\$,]/, '').to_f or 0.0
        unpaid = payment.at('th:contains("Current Balance")').next_element.next_element.text.strip.gsub(/[\$,]/, '').to_f or 0.0
      end

      #puts sewage

      #a.get(balance_url) do |balance|
        #unpaid = balance.at('#current-balance').text.strip.sub(/\$/, '').to_f
        #unpaid = balance.at('td:contains("Current Balance")').next_element.text.strip.sub(/\$/, '').to_f
      #end

      return { :rent => rent, :sewage => sewage, :garbage => garbage, :unpaid => unpaid }
    end
  rescue => e
    puts "#{e.class}: #{e.message}".red
    pp e.backtrace
    return { :error => true }
  end
end



def get_pse
  # TODO
  if ARGV.empty?
    return { :error => true }
  end
  electric = ARGV[0].to_f
  return { :electric => electric }
end



def get_xfinity
  # TODO
  return { :internet => 34.99 }
end



def split_rent(avalon, pse, xfinity)
  total = { :adam => 0.0, :damien => 0.0, :eduardo => 0.0, :spencer => 0.0 }
  sqft = { :adam => 80.65, :damien => 103.1, :eduardo => 104.0, :spencer => 80.65 }
  sqft_total = 368.4
  scale = { :bedroom => 0.6, :common => 0.4 }
  even_split = 1.0 / total.length

  adam_paid = pse[:electric] + xfinity[:internet]

  sqft.each do |name, room_size|
    # Split rent based on how big each person's room is, as we agreed upon
    bedroom_percent = room_size / sqft_total
    common_percent = even_split
    bedroom = avalon[:rent] * bedroom_percent * scale[:bedroom]
    common = avalon[:rent] * common_percent * scale[:common]

    # Add in last month's sewage charges and this month's garbage charges
    garbage = avalon[:garbage] * common_percent
    sewage = avalon[:sewage] * common_percent

    # Subtotal it up
    total[name] = (bedroom.round(2) + common.round(2) + garbage.round(2) + sewage.round(2)).round(2)
  end

  # Adam pays utilities and internet in full, so to make things easy, he pays
  # less rent and everyone else pays more.
  total.each do |name, amount|
    unless name == :adam
      total[name] += (adam_paid * even_split).round(2)
    else
      total[name] -= (adam_paid * even_split * (total.length - 1)).round(2)
    end
    total[name] = total[name].round(2)
  end

  # Now we need to calculate the remainder
  remainder = avalon[:rent] + avalon[:sewage] + avalon[:garbage]

  total.each do |name, amount|
    remainder -= amount
  end

  remainder = remainder.round(2)

  # Now that we have the remainder, subtract it from a random person's total
  # This way, nobody gets to claim that they're King of the Apartment for the
  # month because they paid the extra penny or pennies, or, if they really want
  # to claim such a status, they have to do the math themselves :D
  total[total.keys[rand(total.keys.size)]] += remainder

  return total
end



begin # config loading
  
  unless File.stat('config.json').readable?
    raise 'error opening file'
  end
  
  file = open('config.json')

  $cfg = JSON.parse(file.read)

  unless $cfg.key?('logins')
    raise 'key "logins" not found'
  end
  
  unless $cfg.key?('residents')
    raise 'key "residents" not found'
  end
  
rescue Exception => e
  print 'CONFIG LOAD ERROR: '.red
  puts e.message
end

begin # data fetching
  avalon = get_avalon
  pse = get_pse
  xfinity = get_xfinity
rescue Exception => e
  print 'DATA FETCH ERROR: '.red
  puts e.message
  failed = true
end

#pp avalon
#pp pse
#pp xfinity

unless failed or avalon[:error] or pse[:error] or xfinity[:error]

  print '           Rent: '.magenta
  puts '%.02f' % avalon[:rent]
  print '   Sewage, etc.: '.magenta
  puts '%.02f' % avalon[:sewage]
  print '        Garbage: '.magenta
  puts '%.02f' % avalon[:garbage]
  print 'Unpaid (Avalon): '.magenta
  puts '%.02f' % avalon[:unpaid]

  print 'Utilities (PSE): '.yellow
  puts '%.02f' % pse[:electric]

  print '       Internet: '.light_red
  puts '%.02f' % xfinity[:internet]

  total = split_rent(avalon, pse, xfinity)
  #pp total
  print '           Adam: '.cyan
  puts '%.02f' % total[:adam]
  print '         Damien: '.cyan
  puts '%.02f' % total[:damien]
  print '        Eduardo: '.cyan
  puts '%.02f' % total[:eduardo]
  print '        Spencer: '.cyan
  puts '%.02f' % total[:spencer]
  puts 'Everything worked successfully!'.green
else
  puts 'Some kind of error occurred.'.red
end
