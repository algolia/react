# Extracting custom indexing methods in its own class
class BabelCustomSearchHelper
  def self.hook_each(item, _node)
    return nil if excluded_page(item)

    item[:page_score] = page_score(item)

    # Get a full url, including anchor
    item[:url] = url(item)

    # extract locale
    item[:locale] = (item[:url] && item[:url].scan(/.*-((?:zh|ja|ko)-(?:CN|JP|KR)).html/).flatten.first) || 'en-US'
    item[:localized] = (item[:locale] != 'en-US')

    # Get the full hierarchy of the element, including page name and h1 to h6
    hierarchy =  hierarchy(item)
    return nil if hierarchy.length < 2
    item[:hierarchy] = hierarchy

    # Explode the hierarchy in three parts for display
    item[:category] = hierarchy[0]
    item[:subcategory] = hierarchy[1]
    if hierarchy.length == 2
      item[:display_title] = "Go to #{item[:subcategory]}"
    else
      item[:display_title] = [hierarchy[2], hierarchy[-1]].uniq.compact.join(' › ')
    end

    # Set title as the text for headers, remove title otherwise
    if %w(h1 h2 h3 h4 h5 h6).include?(item[:tag_name])
      item[:title] = item[:text]
      item[:text] = nil
    else
      # Remove title if not a header
      item[:title] = nil
    end

    # Add weight based on tag name and place in page
    item[:weight_tag_name] = weight_tag_name(item)
    item[:weight_order] = weight_order_in_page(item)

    item
  end

  def self.excluded_page(item)
    # Index has no relevant content
    return true if item[:url] == '/index.html'
    # Skip all Round-up summing up other pages
    return true if item[:title].include? 'Community Round-up'
    # Skip all blog pagination pages
    return true if item[:url] =~ %r{^/blog/page\d+/}
    # all other pages are OK
    false
  end

  def self.hierarchy(item)
    hierarchy = []

    # add an extra root level for blog, tips, docs
    hierarchy << 'Blog' if item[:url] =~ %r{^/blog/}
    hierarchy << 'Tips' if item[:url] =~ %r{^/tips/}
    hierarchy << 'Docs' if item[:url] =~ %r{^/docs/}

    # Add parent hierarchy
    hierarchy << item[:title]
    %w(h1 h2 h3 h4 h5 h6).each do |h|
      hierarchy << item[h.to_sym] if item[h.to_sym]
    end

    hierarchy
  end

  def self.page_score(item)
    case item[:url]
    when %r{^/docs/}
      3
    when %r{^/tips/}
      2
    when %r{^/blog/}
      0
    else
      1
    end
  end

  # get the full url with anchor
  def self.url(item)
    anchor = nil
    %w(h6 h5 h4 h3 h2 h1).each do |tag|
      title = item[tag.to_sym]
      next if title.nil?
      anchor = '#' + Redcarpet::Render::HTML.generate_id(title)
      break
    end
    "#{item[:url]}#{anchor}"
  end

  # Set weight based on tag name (h1: 90, h6: 40, p: 0)
  def self.weight_tag_name(item)
    tag_name = item[:tag_name]
    return 0 if tag_name == 'p'
    100 - tag_name.gsub('h', '').to_i * 10
  end

  # Order of the node in the page source
  def self.weight_order_in_page(item)
    item[:objectID].to_s.split('_').last.to_i
  end
end

# Overwrite Algolia Jekyll plugin with custom hooks
class AlgoliaSearchRecordExtractor
  def custom_hook_each(item, node)
    BabelCustomSearchHelper.hook_each(item, node)
  end

  # Add a new record for the h1 of each page,
  # allowing to search for pages by name
  def custom_hook_all(items)
    grouped_by_page = items.group_by do |i|
      "#{i[:category]}-#{i[:subcategory]}"
    end
    grouped_by_page.each do |_, pages|
      page_record = {
        category: pages[0][:category],
        hierarchy: pages[0][:hierarchy],
        subcategory: pages[0][:subcategory],
        tagname: 'h1',
        text: nil,
        title: pages[0][:subcategory],
        display_title: "Go to #{pages[0][:subcategory]}",
        url: pages[0][:url].split('#').first, # remove anchor
        locale: pages[0][:locale],
        localized: pages[0][:localized],
        page_score: pages[0][:page_score],
        weight_tag_name: 90,
        weight_order: -1
      }
      items << page_record
    end
    items
  end

  # We'll keep <code> tags in our records, for better display
  def node_text(node)
    return node.text.gsub('<', '&lt;').gsub('>', '&gt;') if node.text?
    return node.to_s if node.name =~ /code/
    node.children.map { |child| node_text(child) }.join.strip.gsub(/ \#$/, '')
  end
end
