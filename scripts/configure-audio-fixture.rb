require 'xcodeproj'
require 'fileutils'
root=File.expand_path('..',__dir__)
ios=File.join(root,'ios')
FileUtils.mkdir_p(File.join(ios,'AudioFixture'))
FileUtils.cp(File.join(root,'native/fixtures/AudioFixture.swift'), File.join(ios,'AudioFixture/AudioFixture.swift'))
p=Xcodeproj::Project.open(File.join(ios,'osu.xcodeproj'))
t=p.targets.find{|x| x.name=='MimiAudioFixture'} || p.new_target(:application,'MimiAudioFixture',:ios,'18.0')
g=p.main_group.find_subpath('AudioFixture',true);g.set_source_tree('<group>');g.set_path('AudioFixture')
f=g.files.find{|x| x.path=='AudioFixture.swift'} || g.new_file('AudioFixture.swift')
t.source_build_phase.add_file_reference(f) unless t.source_build_phase.files_references.include?(f)
['SubtitlePicture.swift', 'LyricsPainter.swift', 'LyricTrack.swift'].each do |name|
 path = '../../native/ios/' + name
 file = g.files.find{|x| x.path==path} || g.new_file(path)
 t.source_build_phase.add_file_reference(file) unless t.source_build_phase.files_references.include?(file)
end
team=p.targets.find{|x| x.name=='osu'}.build_configurations.map{|c| c.build_settings['DEVELOPMENT_TEAM']}.compact.first
raise 'Configure your Apple team in the osu target first' unless team
t.build_configurations.each{|c| c.build_settings.merge!({'PRODUCT_NAME'=>'MimiAudioFixture','PRODUCT_BUNDLE_IDENTIFIER'=>'com.yuxino.osu.AudioFixture','INFOPLIST_FILE'=>'AudioFixture/Info.plist','GENERATE_INFOPLIST_FILE'=>'NO','SWIFT_VERSION'=>'5.0','IPHONEOS_DEPLOYMENT_TARGET'=>'18.0','CODE_SIGN_STYLE'=>'Automatic','TARGETED_DEVICE_FAMILY'=>'1','DEVELOPMENT_TEAM'=>team})}
info={'CFBundleDisplayName'=>'Osu Audio Test','CFBundleExecutable'=>'$(EXECUTABLE_NAME)','CFBundleIdentifier'=>'$(PRODUCT_BUNDLE_IDENTIFIER)','CFBundleName'=>'$(PRODUCT_NAME)','CFBundlePackageType'=>'APPL','CFBundleShortVersionString'=>'1.0','CFBundleVersion'=>'2','LSRequiresIPhoneOS'=>true,'UILaunchScreen'=>{},'UIBackgroundModes'=>['audio'],'UISupportedInterfaceOrientations'=>['UIInterfaceOrientationPortrait']}
Xcodeproj::Plist.write_to_path(info,File.join(ios,'AudioFixture/Info.plist'))
p.save
scheme=Xcodeproj::XCScheme.new;scheme.add_build_target(t);scheme.set_launch_target(t);scheme.save_as(p.path,'MimiAudioFixture',true)
