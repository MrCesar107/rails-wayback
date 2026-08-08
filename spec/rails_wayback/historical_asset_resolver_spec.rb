# frozen_string_literal: true

RSpec.describe RailsWayback::HistoricalAssetResolver do
  it "resolves exact and type-specific files under historical public" do
    SpecSupport.with_tmp_root do |root|
      materialization = root.join("materialization")
      materialization.join("public/images").mkpath
      materialization.join("public/theme.css").write("historical css")
      materialization.join("public/images/logo.svg").write("historical logo")

      exact = described_class.new.resolve(root: materialization, source: "theme.css")
      typed = described_class.new.resolve(root: materialization, source: "logo.svg", type: :image)

      expect(exact).to have_attributes(public_path: "theme.css", size_bytes: 14)
      expect(typed).to have_attributes(public_path: "images/logo.svg", size_bytes: 15)
      expect(described_class.url(sha: "a" * 40, public_path: "images/logo mark.svg", mount: "/wayback/"))
        .to eq("/wayback/refs/#{"a" * 40}/assets/images/logo%20mark.svg")
    end
  end

  it "rejects traversal, encoded traversal, absolute paths, and escaping symlinks" do
    SpecSupport.with_tmp_root do |root|
      materialization = root.join("materialization")
      public_root = materialization.join("public")
      public_root.mkpath
      root.join("secret.txt").write("secret")
      File.symlink(root.join("secret.txt"), public_root.join("escape.txt"))

      resolver = described_class.new
      unsafe = ["../secret.txt", "%2e%2e/secret.txt", "/secret.txt", "folder\\secret.txt", "escape.txt"]

      expect(unsafe.map { |path| resolver.resolve_public_path(root: materialization, public_path: path) })
        .to all(be_nil)
    end
  end

  it "returns nil when public is absent or the requested file does not exist" do
    SpecSupport.with_tmp_root do |root|
      resolver = described_class.new

      expect(resolver.resolve(root: root, source: "missing.png", type: :image)).to be_nil
    end
  end
end
