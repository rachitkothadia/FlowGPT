#!/usr/bin/env ruby
require 'json'
root=File.expand_path('..',__dir__)
fixtures=JSON.parse(File.read(File.join(root,'Shared/Tests/formatting.json')))
header="#pragma once\n#include <string>\n#include <vector>\nstruct FormatFixture { const char* name; const char* input; const char* expected; };\ninline std::vector<FormatFixture> formattingFixtures(){ return {\n"+fixtures.map{|v|'{'+%w[name input expected].map{|k|'R"fixture('+v.fetch(k)+')fixture"'}.join(',')+'}'}.join(",\n")+"\n}; }\n"
path=File.join(root,'Shared/Tests/Fixtures.h')
if ARGV.include?('--write');File.write(path,header)
else;abort 'Shared formatting fixture header is stale; run Scripts/formatting-fixtures.rb --write' unless File.read(path)==header
end
puts "#{fixtures.size} shared fixture definitions verified"
