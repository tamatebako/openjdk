# frozen_string_literal: true

require "spec_helper"
require "tmpdir"

$LOAD_PATH.unshift(File.expand_path("../tools/lib", __dir__))
require "feedstock"

# tebako#716's language segment of the runtime pair's name is this
# feedstock's distribution identity — the flavor's `implementation`
# (temurin / graalvm; both flavors publish onto the same tag, so the
# segment can never be one hardcoded value). Three sites compose the one
# stem grammar from the same Tebakofile values: tools/pins.rb (the
# workflow's RUNTIME_STEM env), tools/build (the artifacts themselves),
# and Feedstock.runtime_stem (the audit + registry tools' expectation).
# A drift between them publishes names the audit refuses — locked here so
# it fails pre-merge instead.
RSpec.describe "the runtime pair's stem (tebako#716)" do
  def pins_env(asset_platform, flavor)
    out = `ruby #{File.join(REPO_ROOT, "tools/pins.rb")} #{asset_platform} #{flavor} --env 2>/dev/null`
    raise "pins.rb failed for #{flavor}/#{asset_platform}" unless $?.success?

    out.lines.map { |line| line.chomp.split("=", 2) }.to_h
  end

  it "composes the implementation segment from the flavor block, per flavor (never one hardcoded value)" do
    temurin = pins_env("macos-arm64", "temurin")
    graalvm = pins_env("macos-arm64", "graalvm")
    expect(temurin.fetch("RUNTIME_STEM")).to match(/\Atebako-runtime-\d+\.\d+\.\d+-temurin-\d/)
    expect(graalvm.fetch("RUNTIME_STEM")).to match(/\Atebako-runtime-\d+\.\d+\.\d+-graalvm-\d/)
    expect(temurin.fetch("RUNTIME_STEM")).not_to eq(graalvm.fetch("RUNTIME_STEM"))
  end

  it "agrees across every compose site and every matrix leg" do
    # matrix_legs, not the raw flavor × platform cartesian: the include
    # arm's legs (the temurin musl pair) are real legs too, and pins.rb
    # must compose their stems as well.
    Feedstock.matrix_legs.each do |flavor, leg|
      model = Feedstock.runtime_stem(flavor, leg.asset_platform)
      expect(pins_env(leg.asset_platform, flavor).fetch("RUNTIME_STEM"))
        .to eq(model), "tools/pins.rb's RUNTIME_STEM disagrees with Feedstock.runtime_stem for #{flavor}/#{leg.asset_platform}"
    end
  end

  it "threads $IMPLEMENTATION through tools/build's own STEM compose (the artifact-naming site)" do
    build = File.read(File.join(REPO_ROOT, "tools", "build"))
    expect(build).to include('STEM="tebako-runtime-$WRAPPER_TEBAKO-$IMPLEMENTATION-$VERSION-$ASSET_PLATFORM"')
  end

  it "fails named when a flavor carries no usable implementation segment" do
    Dir.mktmpdir do |dir|
      recipe = File.join(dir, "Tebakofile")
      File.write(recipe, <<~YAML)
        runtime: {wrapper_tebako: "9.9.9"}
        flavors:
          temurin:
            upstream: {version: "21.0.12"}
      YAML
      expect { Feedstock.runtime_stem("temurin", "macos-arm64", { "RECIPE_PATH" => recipe }) }
        .to raise_error(Feedstock::FeedstockError, /flavors\.temurin\.implementation/)
    end
  end
end
