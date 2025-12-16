#!/usr/bin/env ruby

require_relative 'lib/event_store'
require_relative 'lib/ics_importer'
require 'tempfile'
require 'time'

puts "=== EventStore and IcsImporter Demo ===\n"

# Create a temporary file for testing
temp_file = Tempfile.new(['demo', '.json'])
puts "Using temp storage: #{temp_file.path}"

# Initialize EventStore
store = CalendarBot::EventStore.new(temp_file.path)
puts "EventStore initialized"

# Test basic CRUD operations
puts "\n--- Testing EventStore CRUD ---"

# Create an event
event = {
  'title' => 'Demo Event',
  'description' => 'A demo event for testing',
  'start_time' => Time.now.iso8601,
  'end_time' => (Time.now + 3600).iso8601,
  'custom' => true
}

created = store.create(event)
puts "Created event: #{created['title']} (ID: #{created['id']})"
puts "Total events: #{store.count}"

# Find by ID
found = store.find_by_id(created['id'])
puts "Found event: #{found['title']}"

# Test ICS import functionality
puts "\n--- Testing ICS Import ---"

ics_content = <<~ICS
BEGIN:VCALENDAR
VERSION:2.0
PRODID:-//Test//Test//EN
BEGIN:VEVENT
UID:demo@example.com
DTSTART:#{Time.now.utc.strftime('%Y%m%dT%H%M%S')}Z
DTEND:#{(Time.now + 3600).utc.strftime('%Y%m%dT%H%M%S')}Z
SUMMARY:ICS Import Demo
DESCRIPTION:Testing ICS import functionality
END:VEVENT
END:VCALENDAR
ICS

temp_ics = Tempfile.new(['demo', '.ics'])
temp_ics.write(ics_content)
temp_ics.close

importer = CalendarBot::IcsImporter.new(store)
result = importer.import_from_file(temp_ics.path)

puts "ICS import result: #{result[:success]}"
puts "Events processed: #{result[:events_processed]}"
puts "Created: #{result[:merge_results][:created]}"
puts "Updated: #{result[:merge_results][:updated]}"
puts "Errors: #{result[:merge_results][:errors]}"

# Show final event count
puts "\n--- Final Results ---"
puts "Total events in store: #{store.count}"

# Show all events
store.all_events.each_with_index do |event, i|
  puts "Event #{i+1}: #{event['title']} (#{event['start_time']})"
  puts "  Custom: #{event['custom']}, Imported: #{event['imported_from_url']}"
end

# Test duplicate detection
puts "\n--- Testing Duplicate Detection ---"
duplicate_event = {
  'title' => 'ICS Import Demo',  # Same title as imported event
  'start_time' => Time.now.utc.strftime('%Y-%m-%dT%H:%M:%SZ'),  # Same start time
  'end_time' => (Time.now + 3600).utc.strftime('%Y-%m-%dT%H:%M:%SZ')
}

result = store.create(duplicate_event)
puts "Duplicate creation result: #{result.nil? ? 'Correctly rejected' : 'ERROR: Should have been rejected'}"
puts "Event count remains: #{store.count}"

# Cleanup
temp_file.close
temp_file.unlink
temp_ics.close
temp_ics.unlink

puts "\n=== Demo completed ==="