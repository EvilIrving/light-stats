#!/usr/bin/env ruby
# frozen_string_literal: true

# Wires a unit-test-bundle target ("LightStatsTests") into the Light Stats
# Xcode project and creates a shared scheme with the Test action enabled.
#
# Idempotent: re-running removes any existing LightStatsTests target/group
# first, so it can be applied to a fresh checkout or re-applied after edits.
#
# Usage: ruby scripts/add_test_target.rb

require 'xcodeproj'

PROJECT_PATH = 'Light Stats.xcodeproj'
APP_TARGET_NAME = 'Light Stats'
TEST_TARGET_NAME = 'LightStatsTests'
TEST_GROUP_PATH = 'LightStatsTests'
TEAM_ID = 'QZZ878S3NS'

project = Xcodeproj::Project.open(PROJECT_PATH)

app_target = project.targets.find { |t| t.name == APP_TARGET_NAME }
raise "App target '#{APP_TARGET_NAME}' not found" unless app_target

# --- Clean up any prior run -------------------------------------------------
project.targets.select { |t| t.name == TEST_TARGET_NAME }.each(&:remove_from_project)
project.root_object.main_group.children
       .select { |c| c.respond_to?(:path) && c.path == TEST_GROUP_PATH }
       .each(&:remove_from_project)

# --- Test target ------------------------------------------------------------
test_target = project.new(Xcodeproj::Project::Object::PBXNativeTarget)
project.targets << test_target
test_target.name = TEST_TARGET_NAME
test_target.product_name = TEST_TARGET_NAME
test_target.product_type = 'com.apple.product-type.bundle.unit-test'
test_target.build_configuration_list =
  Xcodeproj::Project::ProjectHelper.configuration_list(project, :osx, nil, :swift)

# Product reference (.xctest) in the Products group.
product_ref = project.products_group.new_reference("#{TEST_TARGET_NAME}.xctest", :built_products)
product_ref.explicit_file_type = 'wrapper.cfbundle'
product_ref.include_in_index = '0'
product_ref.set_source_tree('BUILT_PRODUCTS_DIR')
test_target.product_reference = product_ref

# Build phases.
test_target.build_phases << project.new(Xcodeproj::Project::Object::PBXSourcesBuildPhase)
test_target.build_phases << project.new(Xcodeproj::Project::Object::PBXFrameworksBuildPhase)
test_target.build_phases << project.new(Xcodeproj::Project::Object::PBXResourcesBuildPhase)

# Depend on the app target and host the tests in it.
test_target.add_dependency(app_target)

host_path = "$(BUILT_PRODUCTS_DIR)/#{APP_TARGET_NAME}.app/Contents/MacOS/#{APP_TARGET_NAME}"
common = {
  'BUNDLE_LOADER' => '$(TEST_HOST)',
  'TEST_HOST' => host_path,
  'PRODUCT_BUNDLE_IDENTIFIER' => 'cain.com.light-stats.tests',
  'PRODUCT_NAME' => '$(TARGET_NAME)',
  'GENERATE_INFOPLIST_FILE' => 'YES',
  'MACOSX_DEPLOYMENT_TARGET' => '14.6',
  'SDKROOT' => 'macosx',
  'SUPPORTED_PLATFORMS' => 'macosx',
  'SUPPORTS_MACCATALYST' => 'NO',
  'SWIFT_VERSION' => '5.0',
  'SWIFT_DEFAULT_ACTOR_ISOLATION' => 'MainActor',
  'SWIFT_APPROACHABLE_CONCURRENCY' => 'YES',
  'SWIFT_EMIT_LOC_STRINGS' => 'NO',
  'DEVELOPMENT_TEAM' => TEAM_ID,
  'CODE_SIGN_STYLE' => 'Automatic',
  'LD_RUNPATH_SEARCH_PATHS' => ['$(inherited)', '@executable_path/../Frameworks', '@loader_path/../Frameworks'],
  'STRING_CATALOG_GENERATE_SYMBOLS' => 'NO'
}

test_target.build_configurations.each do |config|
  config.build_settings.merge!(common)
  config.build_settings['SWIFT_OPTIMIZATION_LEVEL'] = '-Onone' if config.name == 'Debug'
end

# --- Synchronized root group: auto-includes every file under LightStatsTests/
sync_group = project.new(Xcodeproj::Project::Object::PBXFileSystemSynchronizedRootGroup)
sync_group.path = TEST_GROUP_PATH
sync_group.source_tree = '<group>'
project.root_object.main_group.children << sync_group
test_target.file_system_synchronized_groups ||= []
test_target.file_system_synchronized_groups << sync_group

project.save

# --- Shared scheme ----------------------------------------------------------
scheme = Xcodeproj::XCScheme.new
scheme.add_build_target(app_target)
scheme.add_test_target(test_target)
scheme.set_launch_target(app_target)
scheme.save_as(PROJECT_PATH, APP_TARGET_NAME, true)

puts "Added target '#{TEST_TARGET_NAME}' and shared scheme '#{APP_TARGET_NAME}'."
