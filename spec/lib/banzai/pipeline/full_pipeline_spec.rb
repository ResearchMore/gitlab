require 'rails_helper'

describe Banzai::Pipeline::FullPipeline do
  describe 'References' do
    let(:project) { create(:project, :public) }
    let(:issue)   { create(:issue, project: project) }

    it 'handles markdown inside a reference' do
      markdown = "[some `code` inside](#{issue.to_reference})"
      result = described_class.call(markdown, project: project)
      link_content = result[:output].css('a').inner_html
      expect(link_content).to eq('some <code>code</code> inside')
    end

    it 'sanitizes reference HTML' do
      link_label = '<script>bad things</script>'
      markdown = "[#{link_label}](#{issue.to_reference})"
      result = described_class.to_html(markdown, project: project)
      expect(result).not_to include(link_label)
    end

    it 'escapes the data-original attribute on a reference' do
      markdown = %Q{[">bad things](#{issue.to_reference})}
      result = described_class.to_html(markdown, project: project)
      expect(result).to include(%{data-original='\"&gt;bad things'})
    end
  end

  describe 'links are detected as malicious' do
    it 'has tooltips for malicious links' do
      examples = %W[
        http://example.com/evil\u202E3pm.exe
        [evilexe.mp3](http://example.com/evil\u202E3pm.exe)
        rdar://localhost.com/\u202E3pm.exe
        http://one😄two.com
        [Evil-Test](http://one😄two.com)
        http://\u0261itlab.com
        [Evil-GitLab-link](http://\u0261itlab.com)
        ![Evil-GitLab-link](http://\u0261itlab.com.png)
      ]

      examples.each do |markdown|
        result = described_class.call(markdown, project: nil)[:output]
        link   = result.css('a').first

        expect(link[:class]).to include('has-tooltip')
      end
    end

    it 'has no tooltips for safe links' do
      examples = %w[
        http://example.com
        [Safe-Test](http://example.com)
        https://commons.wikimedia.org/wiki/File:اسكرام_2_-_تمنراست.jpg
        [Wikipedia-link](https://commons.wikimedia.org/wiki/File:اسكرام_2_-_تمنراست.jpg)
      ]

      examples.each do |markdown|
        result = described_class.call(markdown, project: nil)[:output]
        link   = result.css('a').first

        expect(link[:class]).to be_nil
      end
    end
  end
end
