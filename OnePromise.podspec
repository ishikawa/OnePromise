Pod::Spec.new do |spec|
  spec.name    = "OnePromise"
  spec.version = "0.4.0"
  spec.summary = "Promise for Swift 2.0 which has no dependencies and fits into one file."

  spec.source_files = "OnePromise.swift"

  spec.homepage = "https://github.com/ishikawa/OnePromise"
  spec.license  = "MIT"
  spec.author   = { "Takanori Ishikawa" => "takanori.ishikawa@gmail.com" }
  spec.source   = { :git => "https://github.com/ishikawa/OnePromise.git", :tag => spec.version.to_s }

  spec.ios.deployment_target = "8.0"
  spec.osx.deployment_target = "10.9"
end
