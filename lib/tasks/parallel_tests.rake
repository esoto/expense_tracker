# Wire parallel_tests rake helpers into Rails (parallel:create, parallel:prepare,
# parallel:load_schema, parallel:rake, parallel_rspec:*).
# Only loaded in test/development environments where the gem is installed.

if Rails.env.development? || Rails.env.test?
  begin
    require "parallel_tests/tasks"
  rescue LoadError
    # parallel_tests gem not bundled — skip silently.
  end
end
