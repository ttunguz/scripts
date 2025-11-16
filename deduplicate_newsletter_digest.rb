#!/usr/bin/env ruby

require 'mail'
require 'digest'
require 'set'
require 'fileutils'

# Add Code Mode API path
require_relative '/Users/tomasztunguz/.claude/code_mode/email_api'

class NewsletterDeduplicator
  def initialize(date_range: "2025-11-14..", dry_run: false)
    @date_range = date_range
    @dry_run = dry_run
    @seen_hashes = Set.new
    @unique_content = {}
    @stats = {
      total_emails: 0,
      total_paragraphs: 0,
      unique_paragraphs: 0,
      duplicate_paragraphs: 0
    }
  end

  def run
    puts "Newsletter Digest Deduplication Tool"
    puts "=" * 70
    puts ""

    # Phase 1: Discover emails
    email_files = discover_emails
    return if email_files.empty?

    # Phase 2: Parse & extract content
    emails = parse_emails(email_files)

    # Phase 3: Deduplicate content
    deduplicate_content(emails)

    # Phase 4: Build compendium
    compendium = build_compendium

    # Phase 5: Send email
    send_compendium(compendium) unless @dry_run

    # Phase 6: Archive originals
    archive_emails(email_files) unless @dry_run

    print_stats
  end

  private

  def discover_emails
    puts "Phase 1: Discovering Newsletter Digest emails..."

    # Use notmuch to find Newsletter Digest emails
    cmd = "notmuch search --output=files 'subject:\"Newsletter Digest\" date:#{@date_range}'"
    email_files = `#{cmd}`.split("\n").select { |f| File.exist?(f) }

    @stats[:total_emails] = email_files.size
    puts "Found #{email_files.size} Newsletter Digest emails"
    puts ""

    email_files
  end

  def parse_emails(email_files)
    puts "Phase 2: Parsing emails..."
    emails = []

    email_files.each_with_index do |file, idx|
      begin
        mail = Mail.read(file)
        emails << {
          file: file,
          mail: mail,
          subject: mail.subject,
          date: mail.date
        }
        print "\rProcessed #{idx + 1}/#{email_files.size} emails"
      rescue => e
        warn "\nWarning: Skipping malformed email #{file}: #{e.message}"
      end
    end

    puts "\n"
    emails
  end

  def extract_sections(email_body)
    sections = {}
    current_section = "HEADER"
    current_subsection = nil
    current_content = []

    email_body.each_line do |line|
      stripped = line.strip

      # Skip pure separator lines (just decoration)
      next if stripped =~ /^[─=\-]{10,}$/

      # Detect main section headers (ALL CAPS, at least 5 chars)
      if stripped =~ /^[A-Z][A-Z ]{4,}:?\s*$/
        # Save previous content
        save_section(sections, current_section, current_subsection, current_content)

        current_section = stripped.gsub(/:$/, '')
        current_subsection = nil
        current_content = []

      # Detect subsection headers (starts with capital, ends with specific keywords)
      elsif stripped =~ /^[A-Z][a-zA-Z ]{3,}(Summary|Headlines|Insights|Metrics|Mentioned|Opportunities):?\s*$/
        # Save previous subsection content
        save_section(sections, current_section, current_subsection, current_content)

        current_subsection = stripped.gsub(/:$/, '')
        current_content = []

      else
        # Regular content line
        current_content << line
      end
    end

    # Save final section
    save_section(sections, current_section, current_subsection, current_content)

    sections
  end

  def save_section(sections, main_section, subsection, content)
    return if content.empty?

    section_name = if subsection
                     "#{main_section} / #{subsection}"
                   else
                     main_section
                   end

    sections[section_name] ||= []
    sections[section_name] << content.join("")
  end

  def extract_paragraphs(section_text)
    # Split by double newlines (paragraph boundary)
    paragraphs = section_text.split(/\n\s*\n/).map(&:strip).reject(&:empty?)

    # Filter out email headers, separators, boilerplate
    paragraphs.reject do |p|
      p =~ /^(From:|To:|Subject:|Date:|Bcc:|Return-Path:|Received:|Message-ID:|X-TUID:|Content-Type:|MIME-Version:)/i ||
      p =~ /^[─=\-]{5,}$/ ||
      p.size < 20  # Skip very short fragments
    end
  end

  def hash_paragraph(text)
    # Normalize whitespace before hashing to catch near-duplicates
    normalized = text.gsub(/\s+/, ' ').strip.downcase
    Digest::SHA256.hexdigest(normalized)
  end

  def deduplicate_content(emails)
    puts "Phase 3: Deduplicating content..."

    emails.each_with_index do |email_data, idx|
      print "\rProcessing email #{idx + 1}/#{emails.size}"

      # Get email body
      mail = email_data[:mail]
      body = if mail.multipart?
               mail.text_part ? mail.text_part.decoded : mail.body.decoded
             else
               mail.body.decoded
             end

      # Force UTF-8 encoding to avoid compatibility errors
      body = body.force_encoding('UTF-8').encode('UTF-8', invalid: :replace, undef: :replace)

      # Extract sections
      sections = extract_sections(body)

      # Process each section
      sections.each do |section_name, section_contents|
        section_contents.each do |section_text|
          paragraphs = extract_paragraphs(section_text)

          paragraphs.each do |para|
            @stats[:total_paragraphs] += 1
            hash = hash_paragraph(para)

            unless @seen_hashes.include?(hash)
              @seen_hashes.add(hash)
              @unique_content[section_name] ||= []
              @unique_content[section_name] << para
              @stats[:unique_paragraphs] += 1
            else
              @stats[:duplicate_paragraphs] += 1
            end
          end
        end
      end
    end

    puts "\n"
  end

  def build_compendium
    puts "Phase 4: Building compendium..."

    compendium = []

    # Header
    compendium << "NEWSLETTER DIGEST COMPENDIUM"
    compendium << "November 14-15, 2025"
    compendium << "Deduplicated from #{@stats[:total_emails]} digest emails"
    compendium << ""
    compendium << "=" * 70
    compendium << ""

    # Section order (prioritize important sections first)
    section_order = [
      "GENERAL",
      "VC DEALS",
      "Executive Summary",
      "Companies Mentioned",
      "Numbers and Metrics",
      "Valuable Insights",
      "Investment Opportunities",
      "AI & MACHINE LEARNING",
      "STARTUPS",
      "TECHNOLOGY"
    ]

    # Add prioritized sections first
    section_order.each do |section|
      next unless @unique_content[section]&.any?
      add_section_to_compendium(compendium, section, @unique_content[section])
    end

    # Add remaining sections (sorted alphabetically)
    remaining_sections = (@unique_content.keys - section_order).sort
    remaining_sections.each do |section|
      next unless @unique_content[section]&.any?
      add_section_to_compendium(compendium, section, @unique_content[section])
    end

    # Footer
    compendium << ""
    compendium << "=" * 70
    compendium << "End of Compendium"
    compendium << ""
    compendium << "Stats:"
    compendium << "- Total emails processed: #{@stats[:total_emails]}"
    compendium << "- Total paragraphs: #{@stats[:total_paragraphs]}"
    compendium << "- Unique paragraphs: #{@stats[:unique_paragraphs]}"
    compendium << "- Duplicates removed: #{@stats[:duplicate_paragraphs]} (#{(@stats[:duplicate_paragraphs].to_f / @stats[:total_paragraphs] * 100).round(1)}%)"

    compendium.join("\n")
  end

  def add_section_to_compendium(compendium, section_name, paragraphs)
    compendium << section_name
    compendium << "-" * 70
    compendium << ""

    paragraphs.each do |paragraph|
      compendium << paragraph
      compendium << ""  # Blank line between paragraphs
    end

    compendium << ""
  end

  def send_compendium(compendium_text)
    puts "Phase 5: Sending compendium email..."

    result = EmailAPI.send(
      to: "tt@theoryvc.com",
      subject: "Newsletter Digest Compendium - Nov 14-15, 2025 (Deduplicated)",
      body: compendium_text,
      force: true
    )

    if result[:success]
      puts "✓ Compendium email sent to tt@theoryvc.com"
    else
      puts "✗ ERROR sending email: #{result[:error]}"
      # Save backup
      backup_file = "/tmp/newsletter_compendium_backup_#{Time.now.to_i}.txt"
      File.write(backup_file, compendium_text)
      puts "  Backup saved to: #{backup_file}"
    end

    puts ""
  end

  def archive_emails(email_files)
    puts "Phase 6: Archiving original emails..."

    # Use notmuch to archive (remove inbox tag)
    system("notmuch tag +archived -inbox -- 'subject:\"Newsletter Digest\" date:#{@date_range}'")

    # Move files from INBOX to archive
    archived_count = 0
    email_files.each do |file|
      next unless file.include?('/INBOX/cur/')

      archive_path = file.gsub('/INBOX/cur/', '/archive/cur/')

      begin
        # Ensure parent directory exists
        dir = File.dirname(archive_path)
        FileUtils.mkdir_p(dir) unless Dir.exist?(dir)

        # Move file to archive
        FileUtils.mv(file, archive_path, force: true)
        archived_count += 1
      rescue => e
        warn "\nWarning: Failed to archive #{file}: #{e.message}"
      end
    end

    puts "✓ Archived #{archived_count} Newsletter Digest emails"
    puts ""
  end

  def print_stats
    puts "=" * 70
    puts "DEDUPLICATION COMPLETE"
    puts "=" * 70
    puts ""
    puts "Total emails processed: #{@stats[:total_emails]}"
    puts "Total paragraphs: #{@stats[:total_paragraphs]}"
    puts "Unique paragraphs: #{@stats[:unique_paragraphs]}"
    puts "Duplicate paragraphs: #{@stats[:duplicate_paragraphs]}"
    puts "Deduplication rate: #{(@stats[:duplicate_paragraphs].to_f / @stats[:total_paragraphs] * 100).round(1)}%"
    puts ""
    puts "Sections found:"
    @unique_content.keys.sort.each do |section|
      puts "  - #{section}: #{@unique_content[section].size} unique paragraphs"
    end
    puts ""
  end
end

# Main execution
if __FILE__ == $0
  # Parse command-line arguments
  dry_run = ARGV.include?('--dry-run')
  date_range = ARGV.find { |arg| arg.start_with?('--date=') }&.split('=')&.last || "2025-11-14.."

  if ARGV.include?('--help')
    puts "Usage: ruby deduplicate_newsletter_digest.rb [OPTIONS]"
    puts ""
    puts "Options:"
    puts "  --dry-run         Run without sending email or archiving"
    puts "  --date=RANGE      Specify date range (default: 2025-11-14..)"
    puts "  --help            Show this help message"
    puts ""
    exit 0
  end

  deduplicator = NewsletterDeduplicator.new(
    date_range: date_range,
    dry_run: dry_run
  )

  deduplicator.run
end
