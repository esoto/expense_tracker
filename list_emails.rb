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

message_ids = imap.search([ 'SINCE', 2.days.ago.strftime('%d-%b-%Y') ])
puts "Found #{message_ids.length} emails"

message_ids.first(5).each do |id|
  env = imap.fetch(id, 'ENVELOPE')[0].attr['ENVELOPE']
  puts "#{id}: #{env.subject}"
end

imap.logout
imap.disconnect
