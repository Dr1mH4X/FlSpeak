use pulldown_cmark::{Event, HeadingLevel, Parser, Tag, TagEnd};
use std::borrow::Cow;

/// 计算字符串在 TS3 ServerQuery 转义后的实际字节长度。
///
/// TS3 协议中，空格转为 `\s`，`/` 转为 `\/`，`|` 转为 `\p`，换行转为 `\n` 等，
/// 均会发生 1 字节 -> 2 字节的长度膨胀。
pub fn ts_escaped_len(s: &str) -> usize {
    let mut len = 0;
    for b in s.bytes() {
        match b {
            b' ' | b'/' | b'|' | b'\n' | b'\r' | b'\t' | b'\x08' | b'\x0c' | b'\x0b' | b'\\' => {
                len += 2;
            }
            _ => len += 1,
        }
    }
    len
}

/// 将 Markdown 文本按 Block 转换为 BBCode，并在转义膨胀预算内完成分包。
///
/// 核心不变量：
/// 1. 分包在顶层 Block（段落、列表、代码块、引用等）边界完成，避免在 BBCode 标签中间断开。
/// 2. 分包长度计算以“TS 转义后的实际字节数”为准，杜绝转义后超限导致的截断或拒收。
pub fn markdown_to_bbcode_packets(markdown: &str, max_escaped_bytes: usize) -> Vec<String> {
    let trimmed = markdown.trim();
    if trimmed.is_empty() {
        return Vec::new();
    }

    let blocks = markdown_to_bbcode_blocks(trimmed);
    if blocks.is_empty() {
        return Vec::new();
    }

    let mut packets: Vec<String> = Vec::new();
    let mut current_packet = String::new();

    for block in blocks {
        let block_escaped_len = ts_escaped_len(&block);

        // 如果单个块本身就超过上限（例如极长的无换行单行文字），强制按字符切分
        if block_escaped_len > max_escaped_bytes {
            if !current_packet.is_empty() {
                packets.push(std::mem::take(&mut current_packet));
            }
            let sub_chunks = split_oversized_block(&block, max_escaped_bytes);
            packets.extend(sub_chunks);
            continue;
        }

        if current_packet.is_empty() {
            current_packet = block;
        } else {
            let combined = format!("{current_packet}\n{block}");
            if ts_escaped_len(&combined) <= max_escaped_bytes {
                current_packet = combined;
            } else {
                packets.push(std::mem::take(&mut current_packet));
                current_packet = block;
            }
        }
    }

    if !current_packet.is_empty() {
        packets.push(current_packet);
    }

    packets
}

/// 将 Markdown 解析为自包含的 BBCode 顶层块列表。
fn markdown_to_bbcode_blocks(markdown: &str) -> Vec<String> {
    let parser = Parser::new(markdown);
    let mut blocks = Vec::new();
    let mut current_block = String::new();
    let mut top_level_depth = 0;
    let mut ignore_text_depth = 0;

    for event in parser {
        match event {
            Event::Start(tag) => {
                if top_level_depth == 0 {
                    current_block.clear();
                }
                top_level_depth += 1;

                match tag {
                    Tag::Paragraph => {}
                    Tag::Heading { level, .. } => {
                        let size = match level {
                            HeadingLevel::H1 => 16,
                            HeadingLevel::H2 => 14,
                            _ => 12,
                        };
                        current_block.push_str(&format!("[size={size}][b]"));
                    }
                    Tag::BlockQuote(_) => {
                        current_block.push_str("[quote]");
                    }
                    Tag::CodeBlock(_) => {
                        current_block.push_str("[code]");
                    }
                    Tag::List(_) => {
                        current_block.push_str("[list]");
                    }
                    Tag::Item => {
                        current_block.push_str("[*]");
                    }
                    Tag::Emphasis => {
                        current_block.push_str("[i]");
                    }
                    Tag::Strong => {
                        current_block.push_str("[b]");
                    }
                    Tag::Strikethrough => {
                        current_block.push_str("[s]");
                    }
                    Tag::Link { dest_url, .. } => {
                        current_block.push_str(&format!("[url={dest_url}]"));
                    }
                    Tag::Image { dest_url, .. } => {
                        current_block.push_str(&format!("[img]{dest_url}[/img]"));
                        ignore_text_depth += 1;
                    }
                    _ => {}
                }
            }
            Event::End(tag_end) => {
                match tag_end {
                    TagEnd::Paragraph => {}
                    TagEnd::Heading(_) => {
                        current_block.push_str("[/b][/size]");
                    }
                    TagEnd::BlockQuote(_) => {
                        current_block.push_str("[/quote]");
                    }
                    TagEnd::CodeBlock => {
                        current_block.push_str("[/code]");
                    }
                    TagEnd::List(_) => {
                        current_block.push_str("[/list]");
                    }
                    TagEnd::Item => {}
                    TagEnd::Emphasis => {
                        current_block.push_str("[/i]");
                    }
                    TagEnd::Strong => {
                        current_block.push_str("[/b]");
                    }
                    TagEnd::Strikethrough => {
                        current_block.push_str("[/s]");
                    }
                    TagEnd::Link => {
                        current_block.push_str("[/url]");
                    }
                    TagEnd::Image if ignore_text_depth > 0 => {
                        ignore_text_depth -= 1;
                    }
                    _ => {}
                }

                if top_level_depth > 0 {
                    top_level_depth -= 1;
                }
                if top_level_depth == 0 {
                    let trimmed = current_block.trim();
                    if !trimmed.is_empty() {
                        blocks.push(trimmed.to_string());
                    }
                    current_block.clear();
                }
            }
            Event::Text(text) => {
                if ignore_text_depth == 0 {
                    current_block.push_str(&text);
                }
            }
            Event::Code(code) => {
                current_block.push_str(&format!("[code]{code}[/code]"));
            }
            Event::HardBreak => {
                current_block.push('\n');
            }
            Event::SoftBreak => {
                current_block.push('\n');
            }
            Event::Rule => {
                if top_level_depth == 0 {
                    blocks.push("[hr]".to_string());
                } else {
                    current_block.push_str("\n[hr]\n");
                }
            }
            Event::Html(html) | Event::InlineHtml(html) => {
                let trimmed = html.trim();
                let lower = trimmed.to_ascii_lowercase();
                if lower == "<u>" {
                    current_block.push_str("[u]");
                } else if lower == "</u>" {
                    current_block.push_str("[/u]");
                } else if lower.starts_with("<color") && lower.ends_with('>') {
                    if let Some(hex) = extract_hex_attr(trimmed) {
                        current_block.push_str(&format!("[color={hex}]"));
                    }
                } else if lower == "</color>" {
                    current_block.push_str("[/color]");
                }
            }
            _ => {}
        }
    }

    if !current_block.trim().is_empty() {
        blocks.push(current_block.trim().to_string());
    }

    blocks
}

/// 超大块兜底切分：按字符边界和转义后预算切分。
fn split_oversized_block(block: &str, max_escaped_bytes: usize) -> Vec<String> {
    let mut chunks = Vec::new();
    let mut current = String::new();

    for ch in block.chars() {
        let mut test = current.clone();
        test.push(ch);
        if ts_escaped_len(&test) > max_escaped_bytes && !current.is_empty() {
            chunks.push(std::mem::take(&mut current));
        }
        current.push(ch);
    }

    if !current.is_empty() {
        chunks.push(current);
    }

    chunks
}

/// 将接收自 TS3 服务端的 BBCode 文本归一化转为标准 Markdown 与扩展内联标记。
///
/// 遵循 YAGNI：
/// 1. 核心常用子集映射为 Markdown（`[b]`, `[i]`, `[u]`, `[s]`, `[url]`, `[img]`, `[code]`, `[quote]`, `[list]`, `[hr]`）。
/// 2. `[size=...]` 较大字号转为 `### ` 标题，其余剥离。
/// 3. `[color=...]` 统一归一化为 `<color hex="#RRGGBB">...</color>`，非法颜色剥离。
/// 4. `[u]...[/u]` 转为 `<u>...</u>`，保留给前端内联下划线渲染。
/// 5. 其余冷门标签平滑剥离。
pub fn bbcode_to_markdown(raw: &str) -> String {
    let mut text = Cow::Borrowed(raw);

    // 1. [hr] -> ---
    text = Cow::Owned(replace_tag_simple(&text, "[hr]", "---"));

    // 2. 颜色 [color=...]...[/color] -> 归一化为统一的 <color hex="#RRGGBB">...</color>
    text = Cow::Owned(transform_color_tag(&text));

    // 3. 字号 [size=...]...[/size] -> 若为大字号映射为 ###，其余保留内部文本
    text = Cow::Owned(transform_size_tag(&text));

    // 4. [b]...[/b] -> **...**
    text = Cow::Owned(replace_paired_tag(&text, "b", "**", "**"));

    // 5. [i]...[/i] -> *...*
    text = Cow::Owned(replace_paired_tag(&text, "i", "*", "*"));

    // 6. [u]...[/u] -> <u>...</u>
    text = Cow::Owned(replace_paired_tag(&text, "u", "<u>", "</u>"));

    // 7. [s]...[/s] -> ~~...~~
    text = Cow::Owned(replace_paired_tag(&text, "s", "~~", "~~"));

    // 8. [url=href]label[/url] -> [label](href) & [url]href[/url] -> [href](href)
    text = Cow::Owned(transform_url_tag(&text));

    // 9. [img]href[/img] -> ![image](href)
    text = Cow::Owned(transform_img_tag(&text));

    // 10. [code]...[/code] -> ```\n...\n```
    text = Cow::Owned(transform_code_tag(&text));

    // 11. [quote]...[/quote] -> > ...
    text = Cow::Owned(transform_quote_tag(&text));

    // 12. [list] 与 [*] -> -
    text = Cow::Owned(transform_list_tag(&text));

    // 13. 剥离其它常见样式标签 [center], [left], [right], [font=...] 等
    text = Cow::Owned(strip_paired_tag(&text, "center"));
    text = Cow::Owned(strip_paired_tag(&text, "left"));
    text = Cow::Owned(strip_paired_tag(&text, "right"));
    text = Cow::Owned(strip_paired_tag(&text, "font"));

    text.into_owned()
}

fn replace_tag_simple(source: &str, target: &str, replacement: &str) -> String {
    let lower_src = source.to_lowercase();
    let lower_target = target.to_lowercase();
    let mut result = String::with_capacity(source.len());
    let mut last = 0;

    for (pos, _) in lower_src.match_indices(&lower_target) {
        result.push_str(&source[last..pos]);
        result.push_str(replacement);
        last = pos + target.len();
    }
    result.push_str(&source[last..]);
    result
}

fn replace_paired_tag(
    source: &str,
    tag: &str,
    open_replacement: &str,
    close_replacement: &str,
) -> String {
    let open_pattern = format!("[{tag}]");
    let close_pattern = format!("[/{tag}]");
    let lower = source.to_lowercase();
    let mut result = String::with_capacity(source.len());
    let mut idx = 0;

    while idx < source.len() {
        if let Some(open_rel) = lower[idx..].find(&open_pattern) {
            let open_pos = idx + open_rel;
            result.push_str(&source[idx..open_pos]);
            let content_start = open_pos + open_pattern.len();

            if let Some(close_rel) = lower[content_start..].find(&close_pattern) {
                let close_pos = content_start + close_rel;
                result.push_str(open_replacement);
                result.push_str(&source[content_start..close_pos]);
                result.push_str(close_replacement);
                idx = close_pos + close_pattern.len();
            } else {
                result.push_str(&source[open_pos..content_start]);
                idx = content_start;
            }
        } else {
            result.push_str(&source[idx..]);
            break;
        }
    }

    result
}

fn strip_paired_tag(source: &str, tag: &str) -> String {
    let open_prefix = format!("[{tag}");
    let close_tag = format!("[/{tag}]");
    let lower = source.to_lowercase();
    let mut result = String::with_capacity(source.len());
    let mut idx = 0;

    while idx < source.len() {
        if let Some(open_rel) = lower[idx..].find(&open_prefix) {
            let open_pos = idx + open_rel;
            result.push_str(&source[idx..open_pos]);

            // 寻找 open tag 的 ']'
            if let Some(bracket_rel) = lower[open_pos..].find(']') {
                let content_start = open_pos + bracket_rel + 1;
                if let Some(close_rel) = lower[content_start..].find(&close_tag) {
                    let close_pos = content_start + close_rel;
                    result.push_str(&source[content_start..close_pos]);
                    idx = close_pos + close_tag.len();
                } else {
                    result.push_str(&source[open_pos..content_start]);
                    idx = content_start;
                }
            } else {
                result.push_str(&source[open_pos..]);
                break;
            }
        } else {
            result.push_str(&source[idx..]);
            break;
        }
    }

    result
}

fn normalize_color_name(name: &str) -> Option<&'static str> {
    match name.to_ascii_lowercase().as_str() {
        "black" => Some("#000000"),
        "white" => Some("#ffffff"),
        "red" => Some("#f44336"),
        "green" => Some("#4caf50"),
        "blue" => Some("#2196f3"),
        "yellow" => Some("#ffeb3b"),
        "orange" => Some("#ff9800"),
        "purple" => Some("#9c27b0"),
        "pink" => Some("#e91e63"),
        "cyan" | "aqua" => Some("#00bcd4"),
        "brown" => Some("#795548"),
        "gray" | "grey" => Some("#9e9e9e"),
        "silver" => Some("#c0c0c0"),
        "gold" => Some("#ffd700"),
        "navy" => Some("#000080"),
        "teal" => Some("#008080"),
        "lime" => Some("#00ff00"),
        "magenta" => Some("#ff00ff"),
        "maroon" => Some("#800000"),
        "olive" => Some("#808000"),
        _ => None,
    }
}

fn normalize_color_hex(raw: &str) -> Option<String> {
    let trimmed = raw.trim().trim_matches(['"', '\'']);
    if let Some(named) = normalize_color_name(trimmed) {
        return Some(named.to_string());
    }
    let hex_part = trimmed.strip_prefix('#').unwrap_or(trimmed);
    if hex_part.is_empty() || !hex_part.chars().all(|c| c.is_ascii_hexdigit()) {
        return None;
    }
    match hex_part.len() {
        3 => {
            let mut out = String::with_capacity(7);
            out.push('#');
            for c in hex_part.chars() {
                out.push(c);
                out.push(c);
            }
            Some(out.to_ascii_lowercase())
        }
        6 => Some(format!("#{}", hex_part.to_ascii_lowercase())),
        8 => Some(format!("#{}", hex_part.to_ascii_lowercase())),
        _ => None,
    }
}

fn extract_hex_attr(html: &str) -> Option<String> {
    let lower = html.to_ascii_lowercase();
    let pos = lower.find("hex=")?;
    let rest = &html[pos + 4..];
    let trimmed = rest.trim_start_matches(['"', '\'']);
    let raw = trimmed
        .chars()
        .take_while(|c| c.is_ascii_alphanumeric() || *c == '#')
        .collect::<String>();
    normalize_color_hex(&raw)
}

fn find_matching_close(source: &str, open_prefix: &str, close_tag: &str) -> Option<usize> {
    let lower = source.to_lowercase();
    let mut depth = 1;
    let mut idx = 0;

    while idx < source.len() && depth > 0 {
        let next_open = lower[idx..].find(open_prefix);
        let next_close = lower[idx..].find(close_tag);

        match (next_open, next_close) {
            (Some(o), Some(c)) if o < c => {
                depth += 1;
                idx += o + open_prefix.len();
            }
            (Some(_), Some(c)) => {
                depth -= 1;
                if depth == 0 {
                    return Some(idx + c);
                }
                idx += c + close_tag.len();
            }
            (None, Some(c)) => {
                depth -= 1;
                if depth == 0 {
                    return Some(idx + c);
                }
                idx += c + close_tag.len();
            }
            _ => break,
        }
    }
    None
}

fn transform_color_tag(source: &str) -> String {
    let lower = source.to_lowercase();
    let open_prefix = "[color=";
    let close_tag = "[/color]";
    let mut result = String::with_capacity(source.len());
    let mut idx = 0;

    while idx < source.len() {
        if let Some(open_rel) = lower[idx..].find(open_prefix) {
            let open_pos = idx + open_rel;
            result.push_str(&source[idx..open_pos]);

            if let Some(bracket_rel) = lower[open_pos..].find(']') {
                let raw_val = &source[open_pos + open_prefix.len()..open_pos + bracket_rel];
                let content_start = open_pos + bracket_rel + 1;

                if let Some(close_rel) =
                    find_matching_close(&source[content_start..], open_prefix, close_tag)
                {
                    let close_pos = content_start + close_rel;
                    let inner = &source[content_start..close_pos];
                    let transformed_inner = transform_color_tag(inner);

                    if let Some(hex) = normalize_color_hex(raw_val) {
                        result
                            .push_str(&format!("<color hex=\"{hex}\">{transformed_inner}</color>"));
                    } else {
                        result.push_str(&transformed_inner);
                    }
                    idx = close_pos + close_tag.len();
                } else {
                    result.push_str(&source[open_pos..content_start]);
                    idx = content_start;
                }
            } else {
                result.push_str(&source[open_pos..]);
                break;
            }
        } else {
            result.push_str(&source[idx..]);
            break;
        }
    }

    result
}

fn transform_size_tag(source: &str) -> String {
    let lower = source.to_lowercase();
    let open_prefix = "[size=";
    let close_tag = "[/size]";
    let mut result = String::with_capacity(source.len());
    let mut idx = 0;

    while idx < source.len() {
        if let Some(open_rel) = lower[idx..].find(open_prefix) {
            let open_pos = idx + open_rel;
            result.push_str(&source[idx..open_pos]);

            if let Some(bracket_rel) = lower[open_pos..].find(']') {
                let size_str = &source[open_pos + open_prefix.len()..open_pos + bracket_rel];
                let content_start = open_pos + bracket_rel + 1;

                if let Some(close_rel) = lower[content_start..].find(close_tag) {
                    let close_pos = content_start + close_rel;
                    let inner = &source[content_start..close_pos];

                    let is_large = size_str.contains('+')
                        || size_str
                            .trim_end_matches(|c: char| !c.is_ascii_digit())
                            .parse::<u32>()
                            .map(|s| s >= 14)
                            .unwrap_or(false);

                    if is_large {
                        result.push_str(&format!("### {inner}"));
                    } else {
                        result.push_str(inner);
                    }

                    idx = close_pos + close_tag.len();
                } else {
                    result.push_str(&source[open_pos..content_start]);
                    idx = content_start;
                }
            } else {
                result.push_str(&source[open_pos..]);
                break;
            }
        } else {
            result.push_str(&source[idx..]);
            break;
        }
    }

    result
}

fn transform_url_tag(source: &str) -> String {
    let lower = source.to_lowercase();
    let mut result = String::with_capacity(source.len());
    let mut idx = 0;

    while idx < source.len() {
        if let Some(open_rel) = lower[idx..].find("[url") {
            let open_pos = idx + open_rel;
            result.push_str(&source[idx..open_pos]);

            if lower[open_pos..].starts_with("[url=") {
                if let Some(bracket_rel) = lower[open_pos..].find(']') {
                    let url = &source[open_pos + 5..open_pos + bracket_rel];
                    let content_start = open_pos + bracket_rel + 1;

                    if let Some(close_rel) = lower[content_start..].find("[/url]") {
                        let close_pos = content_start + close_rel;
                        let label = &source[content_start..close_pos];
                        result.push_str(&format!("[{label}]({url})"));
                        idx = close_pos + 6;
                    } else {
                        result.push_str(&source[open_pos..content_start]);
                        idx = content_start;
                    }
                } else {
                    result.push_str(&source[open_pos..]);
                    break;
                }
            } else if lower[open_pos..].starts_with("[url]") {
                let content_start = open_pos + 5;
                if let Some(close_rel) = lower[content_start..].find("[/url]") {
                    let close_pos = content_start + close_rel;
                    let url = &source[content_start..close_pos];
                    result.push_str(&format!("[{url}]({url})"));
                    idx = close_pos + 6;
                } else {
                    result.push_str(&source[open_pos..content_start]);
                    idx = content_start;
                }
            } else {
                result.push_str(&source[open_pos..open_pos + 4]);
                idx = open_pos + 4;
            }
        } else {
            result.push_str(&source[idx..]);
            break;
        }
    }

    result
}

fn transform_img_tag(source: &str) -> String {
    let lower = source.to_lowercase();
    let mut result = String::with_capacity(source.len());
    let mut idx = 0;

    while idx < source.len() {
        if let Some(open_rel) = lower[idx..].find("[img]") {
            let open_pos = idx + open_rel;
            result.push_str(&source[idx..open_pos]);
            let content_start = open_pos + 5;

            if let Some(close_rel) = lower[content_start..].find("[/img]") {
                let close_pos = content_start + close_rel;
                let url = &source[content_start..close_pos];
                result.push_str(&format!("![image]({url})"));
                idx = close_pos + 6;
            } else {
                result.push_str(&source[open_pos..content_start]);
                idx = content_start;
            }
        } else {
            result.push_str(&source[idx..]);
            break;
        }
    }

    result
}

fn transform_code_tag(source: &str) -> String {
    let lower = source.to_lowercase();
    let mut result = String::with_capacity(source.len());
    let mut idx = 0;

    while idx < source.len() {
        if let Some(open_rel) = lower[idx..].find("[code]") {
            let open_pos = idx + open_rel;
            result.push_str(&source[idx..open_pos]);
            let content_start = open_pos + 6;

            if let Some(close_rel) = lower[content_start..].find("[/code]") {
                let close_pos = content_start + close_rel;
                let code = &source[content_start..close_pos];
                if code.contains('\n') {
                    result.push_str(&format!("```\n{code}\n```"));
                } else {
                    result.push_str(&format!("`{code}`"));
                }
                idx = close_pos + 7;
            } else {
                result.push_str(&source[open_pos..content_start]);
                idx = content_start;
            }
        } else {
            result.push_str(&source[idx..]);
            break;
        }
    }

    result
}

fn transform_quote_tag(source: &str) -> String {
    let lower = source.to_lowercase();
    let mut result = String::with_capacity(source.len());
    let mut idx = 0;

    while idx < source.len() {
        if let Some(open_rel) = lower[idx..].find("[quote]") {
            let open_pos = idx + open_rel;
            result.push_str(&source[idx..open_pos]);
            let content_start = open_pos + 7;

            if let Some(close_rel) = lower[content_start..].find("[/quote]") {
                let close_pos = content_start + close_rel;
                let quote = &source[content_start..close_pos];
                let formatted: Vec<String> =
                    quote.lines().map(|line| format!("> {line}")).collect();
                result.push_str(&formatted.join("\n"));
                idx = close_pos + 8;
            } else {
                result.push_str(&source[open_pos..content_start]);
                idx = content_start;
            }
        } else {
            result.push_str(&source[idx..]);
            break;
        }
    }

    result
}

fn transform_list_tag(source: &str) -> String {
    let lower = source.to_lowercase();
    let mut result = String::with_capacity(source.len());
    let mut idx = 0;

    while idx < source.len() {
        if let Some(open_rel) = lower[idx..].find("[list") {
            let open_pos = idx + open_rel;
            result.push_str(&source[idx..open_pos]);

            if let Some(bracket_rel) = lower[open_pos..].find(']') {
                let content_start = open_pos + bracket_rel + 1;

                if let Some(close_rel) = lower[content_start..].find("[/list]") {
                    let close_pos = content_start + close_rel;
                    let list_body = &source[content_start..close_pos];
                    let items = list_body.split("[*]").skip(1);
                    for item in items {
                        let trimmed = item.trim();
                        if !trimmed.is_empty() {
                            result.push_str(&format!("- {trimmed}\n"));
                        }
                    }
                    idx = close_pos + 7;
                } else {
                    result.push_str(&source[open_pos..content_start]);
                    idx = content_start;
                }
            } else {
                result.push_str(&source[open_pos..]);
                break;
            }
        } else {
            result.push_str(&source[idx..]);
            break;
        }
    }

    result
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn escaped_len_accounts_for_expansion() {
        assert_eq!(ts_escaped_len("a b"), 4); // 'a' (1) + '\s' (2) + 'b' (1)
        assert_eq!(ts_escaped_len("a/b|c"), 7); // 'a'(1) + '\/'(2) + 'b'(1) + '\p'(2) + 'c'(1)
    }

    #[test]
    fn markdown_to_bbcode_converts_core_elements() {
        let md = "# Title\n\n**bold** and *italic* and [link](https://flspeak.org)";
        let packets = markdown_to_bbcode_packets(md, 1024);
        assert_eq!(packets.len(), 1);
        assert!(packets[0].contains("[size=16][b]Title[/b][/size]"));
        assert!(
            packets[0]
                .contains("[b]bold[/b] and [i]italic[/i] and [url=https://flspeak.org]link[/url]")
        );
    }

    #[test]
    fn markdown_to_bbcode_splits_on_block_boundaries_within_budget() {
        let md = "Paragraph 1\n\nParagraph 2\n\nParagraph 3";
        // 限制很小的 byte 预算，强制按 Block 边界分包
        let packets = markdown_to_bbcode_packets(md, 20);
        assert_eq!(packets.len(), 3);
        assert_eq!(packets[0], "Paragraph 1");
        assert_eq!(packets[1], "Paragraph 2");
        assert_eq!(packets[2], "Paragraph 3");
    }

    #[test]
    fn bbcode_to_markdown_normalizes_color_and_underline() {
        let raw = "[b]Bold[/b] [color=red]red text[/color] [u]underlined[/u] [color=#00ff00]green[/color]";
        let md = bbcode_to_markdown(raw);
        assert_eq!(
            md,
            "**Bold** <color hex=\"#f44336\">red text</color> <u>underlined</u> <color hex=\"#00ff00\">green</color>"
        );
    }

    #[test]
    fn bbcode_to_markdown_handles_nested_and_invalid_colors() {
        let nested = "[color=red]outer [color=blue]inner[/color] outer[/color]";
        assert_eq!(
            bbcode_to_markdown(nested),
            "<color hex=\"#f44336\">outer <color hex=\"#2196f3\">inner</color> outer</color>"
        );

        let invalid = "[color=invalid_val]plain text[/color]";
        assert_eq!(bbcode_to_markdown(invalid), "plain text");
    }

    #[test]
    fn markdown_to_bbcode_converts_color_and_underline() {
        let md = r##"<u>underline</u> and <color hex="#f44336">red</color>"##;
        let packets = markdown_to_bbcode_packets(md, 1024);
        assert_eq!(packets.len(), 1);
        assert_eq!(
            packets[0],
            "[u]underline[/u] and [color=#f44336]red[/color]"
        );
    }

    #[test]
    fn bbcode_to_markdown_converts_quotes_and_lists() {
        let raw = "[quote]Quote line[/quote]\n[list][*]Item 1[*]Item 2[/list]";
        let md = bbcode_to_markdown(raw);
        assert!(md.contains("> Quote line"));
        assert!(md.contains("- Item 1"));
        assert!(md.contains("- Item 2"));
    }
}
