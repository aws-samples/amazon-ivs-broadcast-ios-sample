workspace 'BasicBroadcast'

def amazonIVS
  platform :ios, '12.0'
  pod 'AmazonIVSBroadcast', '~> 1.9.1'
end

def amazonIVSStages
  platform :ios, '14.0'
  pod 'AmazonIVSBroadcast/Stages', '~> 1.9.1'
end

target 'BasicBroadcast' do
  amazonIVS
end

target 'ScreenCapture' do
  amazonIVS
end

target 'StagesApp' do
  amazonIVSStages
end
