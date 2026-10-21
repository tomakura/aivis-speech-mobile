#!/usr/bin/env ruby
# frozen_string_literal: true

require 'fileutils'
require 'pathname'
require 'xcodeproj'

ROOT = Pathname(__dir__).join('..').expand_path
APP_DIR = ROOT.join('ios', 'AivisSpeechApp')
PROJECT_PATH = APP_DIR.join('AivisSpeechApp.xcodeproj')
APP_NAME = 'AivisSpeechApp'
PACKAGE_REFERENCES = {
  'AivisSpeechiOS' => '../AivisSpeechiOS',
  'AivisSpeechRuntime' => '../AivisSpeechRuntime',
}.freeze

FileUtils.rm_rf(PROJECT_PATH)
FileUtils.mkdir_p(APP_DIR)

project = Xcodeproj::Project.new(PROJECT_PATH.to_s, false, Xcodeproj::Constants::LAST_KNOWN_OBJECT_VERSION)
project.root_object.attributes['LastUpgradeCheck'] = '2630'
project.root_object.development_region = 'en'

app_target = project.new_target(:application, APP_NAME, :ios, '17.0', project.products_group, :swift)

project.build_configurations.each do |config|
  config.build_settings['SWIFT_VERSION'] = '6.0'
end

app_target.build_configurations.each do |config|
  config.build_settings['PRODUCT_BUNDLE_IDENTIFIER'] = 'com.aivis.speechmobile'
  config.build_settings['PRODUCT_NAME'] = '$(TARGET_NAME)'
  config.build_settings['SWIFT_VERSION'] = '6.0'
  config.build_settings['IPHONEOS_DEPLOYMENT_TARGET'] = '17.0'
  config.build_settings['CODE_SIGN_STYLE'] = 'Automatic'
  config.build_settings['GENERATE_INFOPLIST_FILE'] = 'NO'
  config.build_settings['INFOPLIST_FILE'] = 'Resources/Info.plist'
  config.build_settings['CURRENT_PROJECT_VERSION'] = '1'
  config.build_settings['MARKETING_VERSION'] = '0.1.0'
  config.build_settings['TARGETED_DEVICE_FAMILY'] = '1'
  config.build_settings['SUPPORTS_MACCATALYST'] = 'NO'
  config.build_settings['SUPPORTED_PLATFORMS'] = 'iphoneos iphonesimulator'
  config.build_settings['SUPPORTS_MAC_DESIGNED_FOR_IPHONE_IPAD'] = 'NO'
  config.build_settings['SWIFT_EMIT_LOC_STRINGS'] = 'YES'
  config.build_settings['ASSETCATALOG_COMPILER_GENERATE_SWIFT_ASSET_SYMBOL_EXTENSIONS'] = 'NO'
  config.build_settings['ASSETCATALOG_COMPILER_APPICON_NAME'] = ''
  config.build_settings['ASSETCATALOG_COMPILER_GLOBAL_ACCENT_COLOR_NAME'] = ''
end

sources_group = project.main_group.find_subpath('Sources/AivisSpeechApp', true)
source_ref = sources_group.new_file('Sources/AivisSpeechApp/AivisSpeechApp.swift')
app_target.source_build_phase.add_file_reference(source_ref, true)

resources_group = project.main_group.find_subpath('Resources', true)
assets_ref = resources_group.new_file('Resources/Assets.xcassets')
app_target.resources_build_phase.add_file_reference(assets_ref, true)

PACKAGE_REFERENCES.each do |product_name, relative_path|
  package_ref = project.new(Xcodeproj::Project::Object::XCLocalSwiftPackageReference)
  package_ref.relative_path = relative_path
  project.root_object.package_references << package_ref

  package_product = project.new(Xcodeproj::Project::Object::XCSwiftPackageProductDependency)
  package_product.package = package_ref
  package_product.product_name = product_name
  app_target.package_product_dependencies << package_product

  framework_build_file = project.new(Xcodeproj::Project::Object::PBXBuildFile)
  framework_build_file.product_ref = package_product
  app_target.frameworks_build_phase.files << framework_build_file

  package_dependency = project.new(Xcodeproj::Project::Object::PBXTargetDependency)
  package_dependency.product_ref = package_product
  app_target.dependencies << package_dependency
end

scheme = Xcodeproj::XCScheme.new
scheme.configure_with_targets(app_target, nil, launch_target: true)
scheme.save_as(PROJECT_PATH, APP_NAME, true)

project.save
