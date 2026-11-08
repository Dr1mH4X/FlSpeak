/**
 * verify-md-wrap.mjs
 *
 * Reject Markdown prose paragraphs spanning multiple physical lines.
 * The GFM AST distinguishes paragraphs—including those in lists and blockquotes—from
 * multiline structural nodes (code blocks, tables, HTML blocks).
 *
 * Directly ported from DeepSeek Harness:
 * Source: deepseek-harness/scripts/verify-md-wrap.ts
 * Copyright (c) 2026 DeepSeek
 * Licensed under the MIT License
 *
 * Modified for FlSpeak (2026).
 */

import { readFileSync, readdirSync } from 'node:fs'
import { resolve, relative, join, extname } from 'node:path'
import { fromMarkdown } from 'mdast-util-from-markdown'
import { gfmFromMarkdown } from 'mdast-util-gfm'
import { gfm } from 'micromark-extension-gfm'
import { visit } from 'unist-util-visit'

const root = resolve(import.meta.dirname, '../..')

const IGNORE_DIRS = new Set([
  'node_modules',
  '.git',
  '.dart_tool',
  'build',
  'dist',
  '.delta',
  '.cargo',
  'target',
])

function parseMarkdown(source) {
  return fromMarkdown(source, {
    extensions: [gfm()],
    mdastExtensions: [gfmFromMarkdown()],
  })
}

function maskCustomContainers(source) {
  const lines = source.split('\n')
  if (lines[0] === '---') {
    const closing = lines.indexOf('---', 1)
    if (closing !== -1) {
      for (let index = 0; index <= closing; index++) lines[index] = ''
    }
  }
  return lines.map((line) => (line.trimStart().startsWith(':::') ? '' : line)).join('\n')
}

function findViolations(absPath) {
  const file = relative(root, absPath)
  const source = readFileSync(absPath, 'utf8')
  const parsedSource = maskCustomContainers(source)
  const tree = parseMarkdown(parsedSource)
  const out = []

  visit(tree, (node) => {
    if (node.type === 'paragraph' && node.position) {
      const { start, end } = node.position
      if (end.line > start.line) {
        const firstLine = source.split('\n')[start.line - 1] ?? ''
        out.push({ file, line: start.line, text: firstLine.trim() })
      }
      return 'skip'
    }
  })
  return out
}

function collectMarkdownFiles(dir) {
  const results = []
  const entries = readdirSync(dir, { withFileTypes: true })

  for (const entry of entries) {
    if (entry.isDirectory()) {
      if (IGNORE_DIRS.has(entry.name)) continue
      results.push(...collectMarkdownFiles(join(dir, entry.name)))
    } else if (entry.isFile() && extname(entry.name).toLowerCase() === '.md') {
      results.push(join(dir, entry.name))
    }
  }

  return results
}

const files = collectMarkdownFiles(root)
const allViolations = files.flatMap((f) => findViolations(f))

if (allViolations.length === 0) {
  console.log(`verify-md-wrap: ${files.length} file(s) checked, no hard-wrapped prose paragraphs.`)
  process.exit(0)
}

console.error(`verify-md-wrap: hard-wrapped prose paragraphs found (write one physical line per paragraph):`)
for (const v of allViolations) {
  console.error(`  ${v.file}:${v.line}  ${v.text.slice(0, 80)}${v.text.length > 80 ? '…' : ''}`)
}
process.exit(1)
