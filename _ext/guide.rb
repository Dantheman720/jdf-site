require 'nokogiri'
require 'open-uri'

module Awestruct
  module Extensions
    module Guide
      Change = Struct.new(:sha, :author, :date, :message)

      class Index
        include Guide
        
        def initialize(path_prefix, suffix, layout = 'guide', num_changes = 15, num_contrib_changes = -1)
          @path_prefix = path_prefix
          @suffix = suffix
          @num_changes = num_changes
          @num_contrib_changes = num_contrib_changes
          @layout = layout
        end

        def transform(transformers)
        end

        def execute(site)
          guides = []
          
          site.pages.each do |page|
            if ( page.relative_source_path =~ /^#{@path_prefix}\/(?!index)/ && page.relative_source_path =~ /\.#{@suffix}$/)
              
              guide = OpenStruct.new
              page.guide = guide
              page.layout = @layout
              site.engine.set_urls([page])
              guide.url = page.url
              if page.description.nil?
                page.description = page.guide_summary
              end
              guide.summary = page.description
              
              # FIXME contributors should be listed somewhere on the page, but not automatically authors
              # perhaps as little pictures like on github

              # Add the Contributors to Guide based on Git Commit history
              guide.contributors = page_contributors(page, @num_contrib_changes)

              guide.changes = page_changes(page, @num_changes)

              # NOTE page.content forces the source path to be rendered
              page_content = Nokogiri::HTML(page.content)
              guide.title = page_content.css("h1").first.text
              chapters = []

              page_content.css('h2').each do |header_html|
                chapter = OpenStruct.new
                chapter.text = header_html.inner_html
                # Some processors (e.g. asciidoc) kindly create anchors with ids :-)
                chapter.link_id = header_html.attribute('id')
                # Others (e.g. markdown) don't
                if not chapter.link_id
                  chapter.link_id = chapter.text.gsub(' ', '_').gsub('&#8217;', '_').gsub(/[\(\)\.!]/, '').gsub(/\?/, '').downcase
                  header_html['id'] = chapter.link_id
                end
                chapters << chapter
              end

              if @suffix == 'asciidoc'
                # Asciidoc renders a load of stuff at the top of the page, which we need to extract bits of (e.g. author, title) but we want to dump it for rendering
                guide_content = page_content.css('div#content').first 
                guide_content['id'] = 'guide-content'
                page.rendered_content = guide_content
                # Extract authors
                author = page_content.css('span#author').first
                if author
                  guide.authors = [ author.text ]
                end
              elsif @suffix == 'md'
                # Markdown doesn't have an authors syntax, so all we can do is pray ;-)
                # Look for a paragraph that contains Author: Name only
                # Remove if found
                page_content.css('p').each do |a|
                  if a.text
                    author = a.text[/^(Author: )(.+)$/, 2]
                    if author
                      guide.authors = author.split(',').sort
                      a.remove
                    end
                  end
                end
                # Strip out title
                h1 = page_content.css('h1').first
                if h1
                  h1.remove
                end
                # rebuild links
                page_content.css('a').each do |a|
                  # TDOO make this one regex with capture, but my brain is dead
                  if a['href'] =~ /README.md/
                    href='../' + a['href'][/^(.*README).md/, 1] + '/'
                    if a['href'] =~ /#.*$/
                      href+= '#' + a['href'].match(/#(.*)$/)[1]
                    end
                    a['href'] = href
                  end
                end
                page.rendered_content=page_content
              end

              class << page
                  def render(context)
                    self.rendered_content
                  end

                  def content
                    self.rendered_content
                  end
                end


              # make "extra chapters" a setting of the extension?
              chapter = OpenStruct.new
              chapter.text = 'Share the Knowledge'
              chapter.link_id = 'share'
              chapters << chapter

              guide.chapters = chapters

              page_languages = findLanguages(page)
              page.languages = page_languages if page_languages.size > 0

              guide.languages = page.languages

              # only add the main guide to the guide index (i.e., it doesn't have a locale suffix)
              if !(page.relative_source_path =~ /.*_[a-z]{2}(_[a-z]{2})?\..*/)
                guide.group = page.guide_group
                guide.order = if page.guide_order then page.guide_order else 100 end
                # default guide language is english
                guide.language = site.languages.en
                guides << guide
              end
            end
          end
          
          site.guides = guides
        end

        def findLanguages(page)
          languages = []
          base_page = page.source_path.gsub('.textile', '').gsub(@path_prefix, '').gsub(/\/.*\//, '')
          #puts "Current Base Page #{base_page}"
          Dir.entries(@path_prefix[1..-1]).each do |x|
            if x =~ /(#{base_page})_([a-z]{2}(_[a-z]{2})?)\.(.*)/

              trans_base_name = $1
              trans_lang = $2
              trans_postfix = $4
              #puts "#{trans_base_name} #{trans_lang} #{trans_postfix}"

              trans_page = page.site.pages.find{|e| e.source_path =~ /.*#{trans_base_name}_#{trans_lang}.#{trans_postfix}/}

              trans_page.language_parent = page
              trans_page.language = page.site.languages.send(trans_lang)
              trans_page.language.code = trans_lang
              if !trans_page.translators.nil?
                trans_page.translators.each do |username|
                  page.site.identities.lookup(username).translator = true
                end
              end

              languages << trans_page
            end
          end
          return languages.sort{|a,b| a.language.code <=> b.language.code }
        end
      end

      ##
      # Returns a Array of unique author.name's based on the Git commit history for the given page.
      # Assumes guides are brought in as submodules so opens git rooted in the page's dir
      # The Array is ordered by number of commits done by the authors.
      #
      def page_contributors(page, size)
        authors = Hash.new
        page_dir = page.site.dir.match(/^(.*)(\/)$/)[1] + @path_prefix
        rpath = page.source_path.match(/(#{page_dir})\/(.+)/)[2]
        g = Git.open(page_dir)
        g.log(size == -1 ? nil : size).path(rpath).each do |c|
          if authors[c.author.name]
            authors[c.author.name] = authors[c.author.name] + 1
          elsif
            authors[c.author.name] = 1
          end
        end
        return authors.sort{|a, b| b[1] <=> a[1]}.map{|x| x[0]}
      end

      def page_changes(page, size)
        changes = []
        page_dir = page.site.dir.match(/^(.*)(\/)$/)[1] + @path_prefix
        rpath = page.source_path.match(/(#{page_dir})\/(.+)/)[2]
        g = Git.open(page_dir)
        g.log(size == -1 ? nil : size).path(rpath).each do |c|
          changes << Change.new(c.sha, c.author.name, c.author.date, c.message.split(/\n/)[0].chomp('.').capitalize)
        end
        if changes.length == 0
          changes << Change.new('UNTRACKED', 'You', Time.now, 'Not yet committed')
        end
        changes
      end
    end
  end
end
