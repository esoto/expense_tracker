require_relative 'config/environment'

puts "🔍 Debugging Email Structure"
puts "==========================="

account = EmailAccount.find(2)
require 'net/imap'

begin
  imap_settings = account.imap_settings
  imap = Net::IMAP.new(
    imap_settings[:address],
    port: imap_settings[:port],
    ssl: imap_settings[:enable_ssl]
  )
  
  imap.login(imap_settings[:user_name], imap_settings[:password])
  imap.select('INBOX')
  
  # Find the PTA LEONA transaction email
  message_ids = imap.search(['SINCE', 1.day.ago.strftime('%d-%b-%Y')])
  
  message_ids.each do |msg_id|
    envelope = imap.fetch(msg_id, 'ENVELOPE')[0].attr['ENVELOPE']
    subject = envelope.subject || ''
    
    if subject.include?('PTA LEONA')
      puts "Found PTA LEONA email: #{subject}"
      
      # Get the body structure
      body_structure = imap.fetch(msg_id, 'BODYSTRUCTURE')[0].attr['BODYSTRUCTURE']
      
      puts "\n📋 Email Structure:"
      puts "Multipart: #{body_structure.multipart?}"
      puts "Media Type: #{body_structure.media_type}"
      puts "Subtype: #{body_structure.subtype}"
      
      if body_structure.multipart?
        puts "\n📄 Parts:"
        body_structure.parts.each_with_index do |part, index|
          puts "  Part #{index + 1}:"
          puts "    Type: #{part.media_type}/#{part.subtype}"
          puts "    Encoding: #{part.encoding}"
          
          if part.multipart?
            puts "    Nested parts:"
            part.parts.each_with_index do |nested_part, nested_index|
              puts "      Nested #{nested_index + 1}: #{nested_part.media_type}/#{nested_part.subtype}"
            end
          end
        end
        
        # Try to fetch different parts
        puts "\n🔍 Trying to fetch different parts:"
        
        # Try part 1 (usually plain text)
        begin
          part1 = imap.fetch(msg_id, 'BODY[1]')[0].attr['BODY[1]']
          puts "Part 1 (first 200 chars): #{part1[0..200]}..."
        rescue => e
          puts "Part 1 error: #{e.message}"
        end
        
        # Try part 2 (usually HTML)
        begin
          part2 = imap.fetch(msg_id, 'BODY[2]')[0].attr['BODY[2]']
          puts "Part 2 (first 200 chars): #{part2[0..200]}..."
        rescue => e
          puts "Part 2 error: #{e.message}"
        end
        
        # Try to find and fetch text/plain specifically
        body_structure.parts.each_with_index do |part, index|
          if part.media_type == 'TEXT' && part.subtype == 'PLAIN'
            puts "\n✅ Found text/plain at part #{index + 1}"
            begin
              text_content = imap.fetch(msg_id, "BODY[#{index + 1}]")[0].attr["BODY[#{index + 1}]"]
              puts "Text content (first 500 chars):"
              puts text_content[0..500]
            rescue => e
              puts "Error fetching text part: #{e.message}"
            end
          end
        end
        
      else
        # Single part email
        puts "Single part email"
        body_content = imap.fetch(msg_id, 'BODY[TEXT]')[0].attr['BODY[TEXT]']
        puts "Body (first 200 chars): #{body_content[0..200]}..."
      end
      
      break
    end
  end
  
  imap.logout
  imap.disconnect
  
rescue => e
  puts "Error: #{e.message}"
  puts e.backtrace.first(5)
end