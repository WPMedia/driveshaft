require 'archieml'
require 'nokogiri'

module Driveshaft
  module Exports

    def self.archieml(file, client)
      data = {}

      link = file['exportLinks']['text/html']
      response = client.execute(uri: link)

      raise response.error_message if response.status.to_s != '200'

      html_doc = Nokogiri::HTML(response.body)

      text = Driveshaft::Exports::Archieml.convert_node(html_doc.children[1].children[1])
      text.gsub!(/<[^<>]*>/) do |match|
        match.gsub(/‘|’/, "'")
             .gsub(/“|”/, '"')
      end

      # Remove non-breaking space characters that Google Docs sometimes adds
      text.gsub!("\u00a0", " ")

      data = ::Archieml.load(text)

      # The parser preserves the anchor tags for links in archie, but this breaks on more stories
      # So, we're going to find the more stories key and reformat the anchor tags to be links
      # This is BAD CODE but is stop gap so we can publish
      data.each do |key, values|
        if key == 'moreStories'
          values.each do |hash|
            hash['url'] = Nokogiri::HTML.fragment(hash['url']).text
          end
        end
      end

      return {
        body: JSON.dump(data),
        content_type: 'application/json; charset=utf-8'
      }
    end

    module Archieml

      NODE_TYPES = {
        'text' => lambda { |node|
          return node.content
        },
        'span' => lambda { |node|
          convert_node(node)
        },
        'p' => lambda { |node|
          return convert_node(node) + "\n"
        },
        'a' => lambda { |node|
          return convert_node(node) unless node.attributes['href'] && node.attributes['href'].value

          href = node.attributes['href'].value
          if !href.index('?').nil? && parsed_url = CGI.parse(href)
            href = parsed_url.values[0][0] if parsed_url.keys[0] == 'https://www.google.com/url?q'
          end

          str = "<a href=\"#{href}\">"
          str += convert_node(node)
          str += "</a>"
          return str
        },
        'li' => lambda { |node|
          return '* ' + convert_node(node) + "\n"
        }
      }

      %w(ul ol).each { |tag| NODE_TYPES[tag] = NODE_TYPES['span'] }
      %w(h1 h2 h3 h4 h5 h6 br hr).each { |tag| NODE_TYPES[tag] = NODE_TYPES['p'] }

      def self.convert_node(node)
        str = ''
        node.children.each do |child|
          if func = NODE_TYPES[child.name || child.type]
            str += func.call(child)
          end
        end
        return str
      end

    end
  end
end
