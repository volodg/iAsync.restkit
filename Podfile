platform :ios, '8.0'
use_frameworks!

def import_pods

pod 'iAsync.async'  , :path => '../iAsync.async'
pod 'iAsync.utils'  , :path => '../iAsync.utils'

end

target 'iAsync.restkit', :exclusive => true do
  import_pods
end

target 'iAsync.restkitTests', :exclusive => true do
  import_pods
end
