require 'xcodeproj'
require 'fileutils'

root = File.expand_path(ARGV.fetch(0))
project = Xcodeproj::Project.open(File.join(root, 'MuwaNasheeds.xcodeproj'))
app = project.targets.find { |target| target.product_type == 'com.apple.product-type.application' }
raise 'Missing existing Muwa application target' unless app
test = project.new_target(:ui_test_bundle, 'MuwaInteractionTests', :ios, '17.0')
test.add_dependency(app)
group = project.main_group.new_group('InteractionTests', 'InteractionTests')
FileUtils.mkdir_p(File.join(root, 'InteractionTests'))
FileUtils.cp(File.join(__dir__, 'NativeInteractionTests.swift'), File.join(root, 'InteractionTests/NativeInteractionTests.swift'))
test.add_file_references([group.new_file('NativeInteractionTests.swift')])
test.build_configurations.each do |config|
  config.build_settings.merge!({
    'PRODUCT_BUNDLE_IDENTIFIER' => 'app.muwa.nasheeds.InteractionTests',
    'GENERATE_INFOPLIST_FILE' => 'YES', 'SWIFT_VERSION' => '5.0',
    'TEST_TARGET_NAME' => app.name, 'CODE_SIGNING_ALLOWED' => 'NO',
    'TARGETED_DEVICE_FAMILY' => '1,2'
  })
end
project.save
scheme = Xcodeproj::XCScheme.new
scheme.add_build_target(app)
scheme.add_build_target(test)
scheme.add_test_target(test)
scheme.set_launch_target(app)
scheme.save_as(File.join(root, 'MuwaNasheeds.xcodeproj'), 'MuwaInteractions', true)
