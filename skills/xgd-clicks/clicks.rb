#!/usr/bin/env ruby
# 他社の X.gd 短縮URLのクリック数を、X.gd 公式の分析ページ（x.gd/analytics/<id>）と同じAPIから読む。
# 使い方: ruby clicks.rb <URLまたはID> [--days N]   （既定は過去24時間を1時間刻み。--days は日刻み）
require "json"
require "net/http"
require "uri"

args = ARGV.dup
days = args.include?("--days") ? args.delete_at(args.index("--days") + 1).to_i.tap { args.delete("--days") } : nil
id = args.first.to_s[%r{(?:x\.gd/(?:analytics/)?)?([A-Za-z0-9_-]+)/?\+?\z}, 1]
abort "使い方: ruby clicks.rb <x.gd/ID> [--days N]" unless id

body = { id: id, mode: "last", range: (days || 24).to_s, unit: days ? "day" : "hour", timezone: "Asia/Tokyo", lang: "ja" }
res = Net::HTTP.post(URI("https://x.gd/api/v1/analytics"), body.to_json,
                     "Content-Type" => "application/json", "Origin" => "https://x.gd", "User-Agent" => "Mozilla/5.0")
j = JSON.parse(res.body)
abort "取得できません（status #{j.dig('status', 'code')}）: #{id}" unless j.dig("status", "code") == 200
r = j["results"]

puts "分析ページ: https://x.gd/analytics/#{id}"
puts "x.gd/#{id}  作成 #{r.dig('info', 'created')}（UTC）  累計 #{r['total']}  読み取り #{Time.now.strftime('%F %T')}"
puts
r["count"].each { |c| puts format("%-19s %5d", c["x"], c["y"]) }
puts
%w[ref cc platform].each do |k|
  puts "#{k}: " + (r[k] || []).first(5).map { |c| "#{c['label'] || c['x']} #{c['count'] || c['y']}" }.join(" / ")
end
