require_relative 'config/environment'

account = EmailAccount.find(2)
require 'net/imap'

imap_settings = account.imap_settings
imap = Net::IMAP.new(
  imap_settings[:address],
  port: imap_settings[:port],
  ssl: imap_settings[:enable_ssl]
)

imap.login(imap_settings[:user_name], imap_settings[:password])
imap.select('INBOX')

message_ids = imap.search([ 'SINCE', 3.days.ago.strftime('%d-%b-%Y') ])
puts "Found #{message_ids.length} emails in last 3 days"

bac_emails = []
message_ids.each do |id|
  env = imap.fetch(id, 'ENVELOPE')[0].attr['ENVELOPE']
  subject = env.subject || ''

  if subject.include?('transacci') || subject.include?('Notificaci')
    bac_emails << { id: id, subject: subject }
  end
end

puts "\nBAC transaction emails:"
bac_emails.each do |email|
  puts "#{email[:id]}: #{email[:subject]}"
end

# Use the first BAC email to debug structure
if bac_emails.any?
  first_bac = bac_emails.first
  puts "\n🔍 Debugging structure of: #{first_bac[:subject]}"

  body_structure = imap.fetch(first_bac[:id], 'BODYSTRUCTURE')[0].attr['BODYSTRUCTURE']

  puts "Multipart: #{body_structure.multipart?}"
  puts "Media Type: #{body_structure.media_type}"
  puts "Subtype: #{body_structure.subtype}"

  if body_structure.multipart?
    puts "\nParts:"
    body_structure.parts.each_with_index do |part, index|
      puts "  Part #{index + 1}: #{part.media_type}/#{part.subtype}"

      # Try to fetch this part
      begin
        part_content = imap.fetch(first_bac[:id], "BODY[#{index + 1}]")[0].attr["BODY[#{index + 1}]"]
        puts "    Content preview: #{part_content[0..100]}..."
      rescue => e
        puts "    Error fetching: #{e.message}"
      end
    end
  end
end

imap.logout
imap.disconnect
