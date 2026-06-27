#!/usr/bin/env ruby
# frozen_string_literal: true

# Wires the "FinderMenuExtension" FinderSync app-extension target into the Light
# Stats Xcode project: creates the target, embeds it in the host app's PlugIns,
# and compiles the shared FinderMenu/*.swift into both host and extension.
#
# Idempotent: re-running first strips any prior FinderMenuExtension target,
# groups, embed phase, dependency, and shared-source build files, so it can be
# applied to a fresh checkout or re-applied after edits.
#
# Usage: ruby script/add_finder_extension_target.rb

require 'xcodeproj'

PROJECT_PATH = 'Light Stats.xcodeproj'
APP_TARGET_NAME = 'Light Stats'
EXT_TARGET_NAME = 'FinderMenuExtension'
SHARED_GROUP = 'FinderMenu'
EXT_GROUP = 'FinderMenuExtension'
TEAM_ID = 'QZZ878S3NS'
DEPLOYMENT = '14.6'
EMBED_PHASE_NAME = 'Embed Foundation Extensions'

SHARED_SOURCES = %w[
  FinderMenuShared.swift
  FinderMenuAction.swift
  FinderMenuCommand.swift
  FinderMenuConfig.swift
  FinderMenuRequest.swift
  FinderMenuPresets.swift
  FinderMenuIPCClient.swift
].freeze

project = Xcodeproj::Project.open(PROJECT_PATH)

app_target = project.targets.find { |t| t.name == APP_TARGET_NAME }
raise "App target '#{APP_TARGET_NAME}' not found" unless app_target

# --- Clean up any prior run -------------------------------------------------
# Remove shared-source build files from the host (avoid duplicate compile units).
app_target.source_build_phase.files.dup.each do |bf|
  ref = bf.file_ref
  next unless ref.respond_to?(:path) && ref.path
  bf.remove_from_project if SHARED_SOURCES.include?(File.basename(ref.path))
end

# Remove our embed phase + dependency to the old extension target.
app_target.copy_files_build_phases
          .select { |p| p.name == EMBED_PHASE_NAME }
          .each(&:remove_from_project)
app_target.dependencies
          .select { |d| d.target&.name == EXT_TARGET_NAME }
          .each(&:remove_from_project)

project.targets.select { |t| t.name == EXT_TARGET_NAME }.each(&:remove_from_project)
project.root_object.main_group.children
       .select { |c| c.respond_to?(:path) && [SHARED_GROUP, EXT_GROUP].include?(c.path) }
       .each(&:remove_from_project)
project.products_group.children
       .select { |c| c.respond_to?(:path) && c.path == "#{EXT_TARGET_NAME}.appex" }
       .each(&:remove_from_project)

# --- Extension target -------------------------------------------------------
ext_target = project.new(Xcodeproj::Project::Object::PBXNativeTarget)
project.targets << ext_target
ext_target.name = EXT_TARGET_NAME
ext_target.product_name = EXT_TARGET_NAME
ext_target.product_type = 'com.apple.product-type.app-extension'
ext_target.build_configuration_list =
  Xcodeproj::Project::ProjectHelper.configuration_list(project, :osx, DEPLOYMENT, :swift)

product_ref = project.products_group.new_reference("#{EXT_TARGET_NAME}.appex", :built_products)
product_ref.explicit_file_type = 'wrapper.app-extension'
product_ref.include_in_index = '0'
product_ref.set_source_tree('BUILT_PRODUCTS_DIR')
ext_target.product_reference = product_ref

ext_target.build_phases << project.new(Xcodeproj::Project::Object::PBXSourcesBuildPhase)
ext_target.build_phases << project.new(Xcodeproj::Project::Object::PBXFrameworksBuildPhase)
ext_target.build_phases << project.new(Xcodeproj::Project::Object::PBXResourcesBuildPhase)

ext_settings = {
  'PRODUCT_BUNDLE_IDENTIFIER' => 'cain.com.light-stats.FinderMenuExtension',
  'PRODUCT_NAME' => '$(TARGET_NAME)',
  'INFOPLIST_FILE' => 'FinderMenuExtension/Info.plist',
  'GENERATE_INFOPLIST_FILE' => 'NO',
  'CODE_SIGN_ENTITLEMENTS' => 'FinderMenuExtension/FinderMenuExtension.entitlements',
  'CODE_SIGN_STYLE' => 'Automatic',
  'DEVELOPMENT_TEAM' => TEAM_ID,
  'MACOSX_DEPLOYMENT_TARGET' => DEPLOYMENT,
  'SDKROOT' => 'macosx',
  'SUPPORTED_PLATFORMS' => 'macosx',
  'SUPPORTS_MACCATALYST' => 'NO',
  'SWIFT_VERSION' => '5.0',
  'SKIP_INSTALL' => 'YES',
  # 版本号跟随宿主：扩展的 CFBundleVersion 必须等于父 App，否则校验 / 公证报错。
  # 两者都用占位符，release.yml 经命令行覆盖 MARKETING_VERSION 时扩展一并生效。
  'CURRENT_PROJECT_VERSION' => '2',
  'MARKETING_VERSION' => '1.0.2',
  'SWIFT_EMIT_LOC_STRINGS' => 'NO',
  'STRING_CATALOG_GENERATE_SYMBOLS' => 'NO',
  'LD_RUNPATH_SEARCH_PATHS' => ['$(inherited)', '@executable_path/../../../../Frameworks'],
  'CODE_SIGN_INJECT_BASE_ENTITLEMENTS' => 'YES'
}

ext_target.build_configurations.each do |config|
  config.build_settings.merge!(ext_settings)
  config.build_settings['SWIFT_OPTIMIZATION_LEVEL'] = '-Onone' if config.name == 'Debug'
end

# --- Groups + file references -----------------------------------------------
shared_group = project.root_object.main_group.new_group(SHARED_GROUP, SHARED_GROUP)
SHARED_SOURCES.each do |file|
  ref = shared_group.new_reference(file)
  app_target.source_build_phase.add_file_reference(ref)
  ext_target.source_build_phase.add_file_reference(ref)
end

ext_group = project.root_object.main_group.new_group(EXT_GROUP, EXT_GROUP)
controller_ref = ext_group.new_reference('FinderMenuController.swift')
ext_target.source_build_phase.add_file_reference(controller_ref)
ext_group.new_reference('Info.plist')
ext_group.new_reference('FinderMenuExtension.entitlements')

# --- Embed into host PlugIns ------------------------------------------------
app_target.add_dependency(ext_target)
embed_phase = app_target.new_copy_files_build_phase(EMBED_PHASE_NAME)
embed_phase.symbol_dst_subfolder_spec = :plug_ins
embed_build_file = embed_phase.add_file_reference(ext_target.product_reference, true)
embed_build_file.settings = { 'ATTRIBUTES' => %w[RemoveHeadersOnCopy CodeSignOnCopy] }

project.save

puts "Wired target '#{EXT_TARGET_NAME}' (embedded in '#{APP_TARGET_NAME}' PlugIns)."
