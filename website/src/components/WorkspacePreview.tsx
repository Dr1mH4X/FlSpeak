import React, { useEffect, useMemo, useRef, useState } from 'react';
import type { Locale, TranslationKey } from '../i18n/translations';

interface WorkspacePreviewProps {
  locale: Locale;
  t: (key: TranslationKey, vars?: Record<string, string | number>) => string;
}

type WorkspaceTab = 'messages' | 'media' | 'files' | 'details';

interface PreviewMember {
  id: string;
  name: string;
  role: string;
  avatarColor: string;
  speaking?: boolean;
  muted?: boolean;
  deafened?: boolean;
  away?: boolean;
  pingMs: number;
}

interface PreviewMessage {
  id: string;
  author: string;
  roleBadge?: string;
  avatarColor: string;
  time: string;
  textZh: string;
  textEn: string;
  codeSnippet?: string;
  attachmentTitle?: string;
  attachmentMeta?: string;
}

interface PreviewFileItem {
  name: string;
  isDir: boolean;
  size: string;
  updated: string;
  codecTag?: string;
}

interface PreviewChannel {
  id: string;
  groupZh: string;
  groupEn: string;
  nameZh: string;
  nameEn: string;
  topicZh: string;
  topicEn: string;
  codec: string;
  bitrate: string;
  icon: 'voice' | 'music' | 'code' | 'shield';
  locked?: boolean;
  members: PreviewMember[];
  initialMessages: PreviewMessage[];
  files: PreviewFileItem[];
}

interface PreviewServer {
  id: string;
  shortLabel: string;
  nameZh: string;
  nameEn: string;
  address: string;
  pingMs: number;
  channels: PreviewChannel[];
}

const INITIAL_SERVERS: PreviewServer[] = [
  {
    id: 'srv-core',
    shortLabel: 'FL',
    nameZh: 'FlSpeak 自建语音节点',
    nameEn: 'FlSpeak Self-Hosted Lab',
    address: 'voice.flspeak.lan:9987',
    pingMs: 16,
    channels: [
      {
        id: 'ch-duplex',
        groupZh: '实时语音室',
        groupEn: 'VOICE CHANNELS',
        nameZh: '双工音频实验室',
        nameEn: 'Full-Duplex Audio Lab',
        topicZh: 'Opus 48kHz · 双线程 cpal 独立流 · 零 FFI 音频帧传输',
        topicEn:
          'Opus 48kHz · Dual-thread cpal streams · Zero-FFI audio frames',
        codec: 'Opus Voice (48 kHz / Stereo)',
        bitrate: '96 kbps',
        icon: 'voice',
        members: [
          {
            id: 'm-1',
            name: 'linus_dsp',
            role: 'Audio Engine',
            avatarColor: '#5556C9',
            speaking: true,
            pingMs: 14,
          },
          {
            id: 'm-2',
            name: 'aria_actor',
            role: 'Session Actor',
            avatarColor: '#2B7A78',
            speaking: false,
            pingMs: 19,
          },
          {
            id: 'm-self',
            name: 'Dr1mH4X',
            role: 'Maintainer',
            avatarColor: '#6C5CE7',
            speaking: false,
            pingMs: 16,
          },
        ],
        initialMessages: [
          {
            id: 'msg-1',
            author: 'linus_dsp',
            roleBadge: 'core/audio',
            avatarColor: '#5556C9',
            time: '21:14',
            textZh:
              '已完成采集与播放双流解耦，VAD 门限与软限幅器全部在 Rust 音频线程内闭环运行。',
            textEn:
              'Decoupled capture and playback streams; VAD gate and soft-clipper now run entirely inside the Rust audio thread.',
            codeSnippet:
              'core/audio: capture (cpal) -> Opus encode -> UDP | UDP -> Opus decode -> softclip -> playback',
          },
          {
            id: 'msg-2',
            author: 'aria_actor',
            roleBadge: 'core/session',
            avatarColor: '#2B7A78',
            time: '21:16',
            textZh:
              'LocalSet 会话 Actor 已接管所有 tsclient-rs 协议调用，UI 层只订阅归一化后的状态快照与电平事件。',
            textEn:
              'LocalSet session actor now serializes every tsclient-rs call; Flutter UI only receives normalized snapshots and meter events.',
            attachmentTitle: 'voice-meter-ribbon-telemetry.svg',
            attachmentMeta: '60 Hz RMS Envelope · -14.2 dBFS peak',
          },
          {
            id: 'msg-3',
            author: 'Dr1mH4X',
            roleBadge: 'host',
            avatarColor: '#6C5CE7',
            time: '21:18',
            textZh:
              '试试点击左侧切换语音频道、切换底部麦克风静音，或者切换网页右上角的深浅色模式——工作区状态会 100% 保持。',
            textEn:
              'Try switching channels on the left, toggling mic mute at the bottom, or flipping the page theme — workspace state stays 100% intact.',
          },
        ],
        files: [
          {
            name: 'dsp-presets',
            isDir: true,
            size: '—',
            updated: '2026-10-29 19:40',
          },
          {
            name: 'opus-48k-full-duplex.toml',
            isDir: false,
            size: '4.2 KB',
            updated: '2026-10-29 21:05',
            codecTag: 'TOML',
          },
          {
            name: 'cpal-latency-trace.csv',
            isDir: false,
            size: '128.6 KB',
            updated: '2026-10-29 20:51',
            codecTag: 'CSV',
          },
          {
            name: 'softclip-transfer-curve.png',
            isDir: false,
            size: '342.0 KB',
            updated: '2026-10-28 16:12',
            codecTag: 'PNG',
          },
        ],
      },
      {
        id: 'ch-proto',
        groupZh: '实时语音室',
        groupEn: 'VOICE CHANNELS',
        nameZh: '协议与连接边界',
        nameEn: 'Protocol & SRV Boundary',
        topicZh: '仅解析标准 _ts3._udp SRV · 严禁连接官方云端与遥测主机',
        topicEn:
          'Standard _ts3._udp SRV resolution · Official cloud hosts blocked at core/proto',
        codec: 'Opus Voice (48 kHz / Mono)',
        bitrate: '64 kbps',
        icon: 'shield',
        members: [
          {
            id: 'm-4',
            name: 'kestrel_net',
            role: 'Protocol Guard',
            avatarColor: '#D97706',
            speaking: false,
            pingMs: 22,
          },
          {
            id: 'm-5',
            name: 'vera_srv',
            role: 'DNS Resolver',
            avatarColor: '#059669',
            muted: true,
            pingMs: 27,
          },
        ],
        initialMessages: [
          {
            id: 'msg-p1',
            author: 'kestrel_net',
            roleBadge: 'core/proto',
            avatarColor: '#D97706',
            time: '19:42',
            textZh:
              'FORBIDDEN_HOST_SUFFIXES 已在连接与远程图片抓取两端共用，任何指向 myteamspeak.com 的请求都会在边界直接拒绝。',
            textEn:
              'FORBIDDEN_HOST_SUFFIXES is enforced across both session connect and remote image fetching — official cloud domains are rejected at the boundary.',
            codeSnippet:
              'assert!(check_self_hosted_target("voice.example.org:9987").is_ok());',
          },
          {
            id: 'msg-p2',
            author: 'vera_srv',
            roleBadge: 'dns/srv',
            avatarColor: '#059669',
            time: '19:49',
            textZh:
              'SRV 解析后也会对最终目标主机再执行一次自治边界校验，防止通过 CNAME/SRV 绕过检查。',
            textEn:
              'Post-SRV target hosts are re-verified against the forbidden suffix list to prevent CNAME or SRV redirection bypasses.',
          },
        ],
        files: [
          {
            name: 'connection-boundary-spec.md',
            isDir: false,
            size: '14.8 KB',
            updated: '2026-10-28 14:20',
            codecTag: 'MD',
          },
          {
            name: 'srv-lookup-vectors.json',
            isDir: false,
            size: '8.4 KB',
            updated: '2026-10-27 11:05',
            codecTag: 'JSON',
          },
        ],
      },
      {
        id: 'ch-music',
        groupZh: '战术与编队',
        groupEn: 'SQUAD & ACOUSTIC',
        nameZh: '高码率声学测试间',
        nameEn: 'Hi-Fi Acoustic Chamber',
        topicZh: 'Opus Music 128kbps · 频道文件直传与瞬态通知演练',
        topicEn:
          'Opus Music 128kbps · Direct channel file transfers & transient notices',
        codec: 'Opus Music (48 kHz / Stereo)',
        bitrate: '128 kbps',
        icon: 'music',
        locked: true,
        members: [
          {
            id: 'm-6',
            name: 'sora_mix',
            role: 'Acoustic QA',
            avatarColor: '#7C3AED',
            speaking: true,
            pingMs: 18,
          },
        ],
        initialMessages: [
          {
            id: 'msg-m1',
            author: 'sora_mix',
            roleBadge: 'opus/music',
            avatarColor: '#7C3AED',
            time: '20:05',
            textZh:
              '当前房间开启了 Opus Music 立体声编码，适合测试多路语音叠加时的软限幅防爆音表现。',
            textEn:
              'Opus Music stereo mode is active in this room for multi-speaker superposition and soft-clip headroom testing.',
          },
        ],
        files: [
          {
            name: 'pink-noise-reference-48k.wav',
            isDir: false,
            size: '6.4 MB',
            updated: '2026-10-29 18:00',
            codecTag: 'WAV',
          },
          {
            name: 'multitone-headroom-test.flac',
            isDir: false,
            size: '4.1 MB',
            updated: '2026-10-26 22:15',
            codecTag: 'FLAC',
          },
        ],
      },
      {
        id: 'ch-afk',
        groupZh: '静音归档',
        groupEn: 'QUIET ZONE',
        nameZh: '挂机休息室 (AFK)',
        nameEn: 'AFK & Bench',
        topicZh: '自动静音频道 · 低功耗待机',
        topicEn: 'Auto-muted resting channel · Zero voice egress',
        codec: 'Opus Voice (24 kHz / Mono)',
        bitrate: '32 kbps',
        icon: 'code',
        members: [
          {
            id: 'm-7',
            name: 'noah_ci',
            role: 'Build Bot',
            avatarColor: '#64748B',
            away: true,
            muted: true,
            deafened: true,
            pingMs: 31,
          },
        ],
        initialMessages: [
          {
            id: 'msg-a1',
            author: 'noah_ci',
            roleBadge: 'ci/runner',
            avatarColor: '#64748B',
            time: '18:00',
            textZh:
              '全平台构建流水线待命中，离开状态下语音发送门控自动闭合。',
            textEn:
              'Multi-platform release pipeline on standby; voice egress gate is automatically closed while away.',
          },
        ],
        files: [
          {
            name: 'release-matrix-checksums.txt',
            isDir: false,
            size: '2.1 KB',
            updated: '2026-10-27 09:30',
            codecTag: 'TXT',
          },
        ],
      },
    ],
  },
  {
    id: 'srv-guild',
    shortLabel: 'RS',
    nameZh: 'Rust 语音编解码节点',
    nameEn: 'Rust Audio Codec Node',
    address: 'ts3.rust-audio.internal:9987',
    pingMs: 24,
    channels: [
      {
        id: 'ch-rust-main',
        groupZh: '核心开发组',
        groupEn: 'CORE DEV',
        nameZh: 'tsclient-rs 联调室',
        nameEn: 'tsclient-rs Integration',
        topicZh: 'TS3/TS6 握手、BBCode/Markdown 渲染与频道图标同步',
        topicEn:
          'TS3/TS6 handshake, BBCode/Markdown formatting & channel icon sync',
        codec: 'Opus Voice (48 kHz / Stereo)',
        bitrate: '96 kbps',
        icon: 'voice',
        members: [
          {
            id: 'm-r1',
            name: 'ferris_ts',
            role: 'Packet Parser',
            avatarColor: '#E11D48',
            speaking: true,
            pingMs: 21,
          },
          {
            id: 'm-self',
            name: 'Dr1mH4X',
            role: 'Maintainer',
            avatarColor: '#6C5CE7',
            speaking: false,
            pingMs: 24,
          },
        ],
        initialMessages: [
          {
            id: 'msg-r1',
            author: 'ferris_ts',
            roleBadge: 'proto',
            avatarColor: '#E11D48',
            time: '20:41',
            textZh:
              '欢迎切换到第二个自建服务器节点！频道文件树与成员状态均已按当前服务器隔离。',
            textEn:
              'Switched to the second self-hosted server node! Channel trees and member rosters are isolated per session.',
          },
        ],
        files: [
          {
            name: 'packet-framing-dump.pcap',
            isDir: false,
            size: '512.0 KB',
            updated: '2026-10-30 15:10',
            codecTag: 'PCAP',
          },
        ],
      },
    ],
  },
];

const MEDIA_ITEMS = [
  {
    id: 'media-1',
    channelId: 'ch-duplex',
    titleZh: '双线程 cpal + Opus 实时电平波形',
    titleEn: 'Dual-thread cpal + Opus Live Waveform',
    sender: 'linus_dsp',
    time: '21:14',
    dims: '1920 × 1080 · SVG',
    accent:
      'linear-gradient(135deg, rgba(85,86,201,0.32), rgba(63,191,135,0.28))',
  },
  {
    id: 'media-2',
    channelId: 'ch-duplex',
    titleZh: 'LocalSet Session Actor 状态机拓扑',
    titleEn: 'LocalSet Session Actor Topology',
    sender: 'aria_actor',
    time: '21:16',
    dims: '1600 × 960 · PNG',
    accent:
      'linear-gradient(135deg, rgba(43,122,120,0.34), rgba(194,193,255,0.24))',
  },
  {
    id: 'media-3',
    channelId: 'ch-proto',
    titleZh: '_ts3._udp SRV 自治边界拦截示意',
    titleEn: '_ts3._udp SRV Self-Hosted Boundary Check',
    sender: 'kestrel_net',
    time: '19:42',
    dims: '1440 × 900 · PNG',
    accent:
      'linear-gradient(135deg, rgba(217,119,6,0.28), rgba(85,86,201,0.26))',
  },
  {
    id: 'media-4',
    channelId: 'ch-music',
    titleZh: 'Opus 128kbps 软限幅失真度频谱',
    titleEn: 'Opus 128kbps Soft-Clip Harmonic Spectrum',
    sender: 'sora_mix',
    time: '20:05',
    dims: '2048 × 1152 · FLAC/PNG',
    accent:
      'linear-gradient(135deg, rgba(124,58,237,0.32), rgba(63,191,135,0.25))',
  },
];

const BAR_COUNT = 26;

export const WorkspacePreview: React.FC<WorkspacePreviewProps> = ({
  locale,
  t,
}) => {
  const stageRef = useRef<HTMLDivElement | null>(null);
  const [tiltProgress, setTiltProgress] = useState<number>(0);

  const [sidebarExpanded, setSidebarExpanded] = useState<boolean>(false);
  const [selectedServerId, setSelectedServerId] = useState<string>('srv-core');
  const [selectedChannelId, setSelectedChannelId] =
    useState<string>('ch-duplex');
  const [voiceChannelId, setVoiceChannelId] = useState<string>('ch-duplex');
  const [voiceConnected, setVoiceConnected] = useState<boolean>(true);
  const [activeTab, setActiveTab] = useState<WorkspaceTab>('messages');
  const [isMuted, setIsMuted] = useState<boolean>(false);
  const [isDeafened, setIsDeafened] = useState<boolean>(false);
  const [isAway, setIsAway] = useState<boolean>(false);
  const [mediaScope, setMediaScope] = useState<'channel' | 'server'>('channel');
  const [composerText, setComposerText] = useState<string>('');
  const [customMessages, setCustomMessages] = useState<
    Record<string, PreviewMessage[]>
  >({});
  const [transientNotice, setTransientNotice] = useState<string | null>(null);
  const [meterPhase, setMeterPhase] = useState<number>(0);

  useEffect(() => {
    const prefersReducedMotion =
      typeof window !== 'undefined' &&
      window.matchMedia?.('(prefers-reduced-motion: reduce)').matches;
    if (prefersReducedMotion) {
      setTiltProgress(1);
      return;
    }

    let rafId = 0;
    const updateTilt = () => {
      const el = stageRef.current;
      if (!el) return;
      const rect = el.getBoundingClientRect();
      const vh = window.innerHeight || 900;
      const startY = vh * 0.86;
      const endY = vh * 0.26;
      const raw = (startY - rect.top) / Math.max(1, startY - endY);
      const clamped = Math.min(1, Math.max(0, raw));
      const eased = 1 - Math.pow(1 - clamped, 3);
      setTiltProgress(eased);
    };

    const onScroll = () => {
      cancelAnimationFrame(rafId);
      rafId = requestAnimationFrame(updateTilt);
    };

    updateTilt();
    window.addEventListener('scroll', onScroll, { passive: true });
    window.addEventListener('resize', onScroll, { passive: true });
    return () => {
      cancelAnimationFrame(rafId);
      window.removeEventListener('scroll', onScroll);
      window.removeEventListener('resize', onScroll);
    };
  }, []);

  useEffect(() => {
    if (!voiceConnected || isDeafened) return;
    const prefersReducedMotion =
      typeof window !== 'undefined' &&
      window.matchMedia?.('(prefers-reduced-motion: reduce)').matches;
    if (prefersReducedMotion) return;

    const timer = window.setInterval(() => {
      setMeterPhase((prev) => (prev + 1) % 360);
    }, 110);
    return () => window.clearInterval(timer);
  }, [voiceConnected, isDeafened]);

  useEffect(() => {
    if (!transientNotice) return;
    const timer = window.setTimeout(() => {
      setTransientNotice(null);
    }, 2600);
    return () => window.clearTimeout(timer);
  }, [transientNotice]);

  const currentServer = useMemo(
    () =>
      INITIAL_SERVERS.find((s) => s.id === selectedServerId) ||
      INITIAL_SERVERS[0],
    [selectedServerId]
  );

  const currentChannel = useMemo(
    () =>
      currentServer.channels.find((c) => c.id === selectedChannelId) ||
      currentServer.channels[0],
    [currentServer, selectedChannelId]
  );

  const activeVoiceChannel = useMemo(
    () =>
      currentServer.channels.find((c) => c.id === voiceChannelId) ||
      currentServer.channels[0],
    [currentServer, voiceChannelId]
  );

  const handleSelectServer = (srv: PreviewServer) => {
    setSelectedServerId(srv.id);
    const firstCh = srv.channels[0];
    if (firstCh) {
      setSelectedChannelId(firstCh.id);
      setVoiceChannelId(firstCh.id);
      setVoiceConnected(true);
    }
  };

  const handleSelectChannel = (ch: PreviewChannel) => {
    setSelectedChannelId(ch.id);
    setVoiceChannelId(ch.id);
    if (!voiceConnected) {
      setVoiceConnected(true);
    }
  };

  const handleToggleMute = () => {
    setIsMuted((prev) => {
      const next = !prev;
      if (!next && isDeafened) {
        setIsDeafened(false);
      }
      return next;
    });
  };

  const handleToggleDeafen = () => {
    setIsDeafened((prev) => {
      const next = !prev;
      if (next) {
        setIsMuted(true);
      }
      return next;
    });
  };

  const handleToggleAway = () => {
    setIsAway((prev) => !prev);
  };

  const handleSendMessage = (e: React.FormEvent) => {
    e.preventDefault();
    const trimmed = composerText.trim();
    if (!trimmed) return;

    const now = new Date();
    const hh = String(now.getHours()).padStart(2, '0');
    const mm = String(now.getMinutes()).padStart(2, '0');

    const newMsg: PreviewMessage = {
      id: `user-msg-${Date.now()}`,
      author: 'Dr1mH4X',
      roleBadge: 'you',
      avatarColor: '#6C5CE7',
      time: `${hh}:${mm}`,
      textZh: trimmed,
      textEn: trimmed,
    };

    setCustomMessages((prev) => ({
      ...prev,
      [currentChannel.id]: [...(prev[currentChannel.id] || []), newMsg],
    }));
    setComposerText('');
  };

  const channelMessages = useMemo(() => {
    const base = currentChannel.initialMessages;
    const added = customMessages[currentChannel.id] || [];
    return [...base, ...added];
  }, [currentChannel, customMessages]);

  const effectiveMembers = useMemo(() => {
    const base = currentChannel.members.filter((m) => m.id !== 'm-self');
    if (voiceConnected && voiceChannelId === currentChannel.id) {
      base.push({
        id: 'm-self',
        name: 'Dr1mH4X',
        role: 'Maintainer',
        avatarColor: '#6C5CE7',
        speaking: !isMuted && !isDeafened && !isAway,
        muted: isMuted,
        deafened: isDeafened,
        away: isAway,
        pingMs: currentServer.pingMs,
      });
    }
    return base;
  }, [
    currentChannel,
    voiceConnected,
    voiceChannelId,
    isMuted,
    isDeafened,
    isAway,
    currentServer.pingMs,
  ]);

  const anySpeaking = useMemo(
    () =>
      voiceConnected &&
      !isDeafened &&
      effectiveMembers.some((m) => m.speaking && !m.muted && !m.away),
    [voiceConnected, isDeafened, effectiveMembers]
  );

  const groupedChannels = useMemo(() => {
    const map = new Map<string, PreviewChannel[]>();
    for (const ch of currentServer.channels) {
      const label = locale === 'zh' ? ch.groupZh : ch.groupEn;
      const list = map.get(label) || [];
      list.push(ch);
      map.set(label, list);
    }
    return Array.from(map.entries());
  }, [currentServer.channels, locale]);

  const rotateXDeg = (1 - tiltProgress) * 18;
  const scaleVal = 0.93 + tiltProgress * 0.07;

  const channelTitle =
    locale === 'zh' ? currentChannel.nameZh : currentChannel.nameEn;
  const channelTopic =
    locale === 'zh' ? currentChannel.topicZh : currentChannel.topicEn;
  const serverTitle =
    locale === 'zh' ? currentServer.nameZh : currentServer.nameEn;

  return (
    <div id="workspace" ref={stageRef} className="workspace-preview-stage">
      <div className="workspace-preview-caption-row">
        <span className="workspace-preview-badge">
          <span className="workspace-badge-dot" aria-hidden="true" />
          {t('previewBadge')}
        </span>
        <span className="workspace-preview-hint">{t('previewHint')}</span>
      </div>

      <div
        className="workspace-3d-frame"
        style={{
          transform: `perspective(1600px) rotateX(${rotateXDeg.toFixed(2)}deg) scale(${scaleVal.toFixed(4)})`,
        }}
      >
        <div
          className="fls-workspace-shell"
          role="region"
          aria-label={t('previewBadge')}
        >
          <aside
            className={`fls-nav-sidebar ${sidebarExpanded ? 'is-expanded' : ''}`}
          >
            <div className="fls-nav-top">
              <button
                type="button"
                className="fls-sidebar-item"
                onClick={() => setSidebarExpanded((prev) => !prev)}
                aria-label={
                  sidebarExpanded
                    ? t('previewSidebarCollapse')
                    : t('previewSidebarExpand')
                }
              >
                <span className="fls-sidebar-icon">
                  {sidebarExpanded ? (
                    <svg
                      viewBox="0 0 24 24"
                      width="20"
                      height="20"
                      fill="none"
                      stroke="currentColor"
                      strokeWidth="2"
                      strokeLinecap="round"
                    >
                      <path d="M19 12H9M13 8l-4 4 4 4M5 5v14" />
                    </svg>
                  ) : (
                    <svg
                      viewBox="0 0 24 24"
                      width="20"
                      height="20"
                      fill="none"
                      stroke="currentColor"
                      strokeWidth="2"
                      strokeLinecap="round"
                    >
                      <path d="M4 7h16M4 12h16M4 17h16" />
                    </svg>
                  )}
                </span>
                {sidebarExpanded && (
                  <span className="fls-sidebar-label">
                    {t('previewSidebarCollapse')}
                  </span>
                )}
              </button>

              <button
                type="button"
                className="fls-sidebar-item"
                onClick={() => setActiveTab('messages')}
                aria-label={t('previewHome')}
              >
                <span className="fls-sidebar-icon">
                  <svg
                    viewBox="0 0 24 24"
                    width="20"
                    height="20"
                    fill="none"
                    stroke="currentColor"
                    strokeWidth="2"
                    strokeLinecap="round"
                    strokeLinejoin="round"
                  >
                    <path d="M3 10.5L12 3l9 7.5V20a1 1 0 0 1-1 1h-5.5v-6h-5v6H4a1 1 0 0 1-1-1v-9.5z" />
                  </svg>
                </span>
                {sidebarExpanded && (
                  <span className="fls-sidebar-label">{t('previewHome')}</span>
                )}
              </button>
            </div>

            <div className="fls-sidebar-divider" />

            <div className="fls-sidebar-servers">
              {INITIAL_SERVERS.map((srv) => {
                const isSelected = srv.id === currentServer.id;
                const sName = locale === 'zh' ? srv.nameZh : srv.nameEn;
                return (
                  <button
                    key={srv.id}
                    type="button"
                    className={`fls-sidebar-server-btn ${isSelected ? 'is-selected' : ''}`}
                    onClick={() => handleSelectServer(srv)}
                    aria-label={sName}
                  >
                    <span
                      className={`fls-server-pill-bar ${isSelected ? 'is-active' : ''}`}
                      aria-hidden="true"
                    />
                    <span className="fls-server-avatar">
                      {srv.shortLabel}
                      {isSelected && voiceConnected && (
                        <span
                          className="fls-server-live-dot"
                          aria-hidden="true"
                        />
                      )}
                    </span>
                    {sidebarExpanded && (
                      <span className="fls-sidebar-label">{sName}</span>
                    )}
                  </button>
                );
              })}

              <button
                type="button"
                className="fls-sidebar-item is-subtle"
                onClick={() =>
                  handleSelectServer(
                    currentServer.id === 'srv-core'
                      ? INITIAL_SERVERS[1]
                      : INITIAL_SERVERS[0]
                  )
                }
                aria-label={t('previewAddServer')}
              >
                <span className="fls-sidebar-icon">
                  <svg
                    viewBox="0 0 24 24"
                    width="19"
                    height="19"
                    fill="none"
                    stroke="currentColor"
                    strokeWidth="2.1"
                    strokeLinecap="round"
                  >
                    <path d="M12 5v14M5 12h14" />
                  </svg>
                </span>
                {sidebarExpanded && (
                  <span className="fls-sidebar-label">
                    {t('previewAddServer')}
                  </span>
                )}
              </button>
            </div>

            <div className="fls-nav-bottom">
              <button
                type="button"
                className="fls-sidebar-item"
                onClick={() => setActiveTab('details')}
                aria-label={t('previewSettings')}
              >
                <span className="fls-sidebar-icon">
                  <svg
                    viewBox="0 0 24 24"
                    width="19"
                    height="19"
                    fill="none"
                    stroke="currentColor"
                    strokeWidth="1.95"
                    strokeLinecap="round"
                    strokeLinejoin="round"
                  >
                    <circle cx="12" cy="12" r="3.2" />
                    <path d="M19.4 15a1.65 1.65 0 0 0 .33 1.82l.06.06a2 2 0 1 1-2.83 2.83l-.06-.06a1.65 1.65 0 0 0-1.82-.33 1.65 1.65 0 0 0-1 1.51V21a2 2 0 1 1-4 0v-.09A1.65 1.65 0 0 0 9 19.4a1.65 1.65 0 0 0-1.82.33l-.06.06a2 2 0 1 1-2.83-2.83l.06-.06a1.65 1.65 0 0 0 .33-1.82 1.65 1.65 0 0 0-1.51-1H3a2 2 0 1 1 0-4h.09A1.65 1.65 0 0 0 4.6 9a1.65 1.65 0 0 0-.33-1.82l-.06-.06a2 2 0 1 1 2.83-2.83l.06.06a1.65 1.65 0 0 0 1.82.33H9a1.65 1.65 0 0 0 1-1.51V3a2 2 0 1 1 4 0v.09a1.65 1.65 0 0 0 1 1.51 1.65 1.65 0 0 0 1.82-.33l.06-.06a2 2 0 1 1 2.83 2.83l-.06.06a1.65 1.65 0 0 0-.33 1.82V9c.26.6.77 1.02 1.51 1H21a2 2 0 1 1 0 4h-.09a1.65 1.65 0 0 0-1.51 1z" />
                  </svg>
                </span>
                {sidebarExpanded && (
                  <span className="fls-sidebar-label">
                    {t('previewSettings')}
                  </span>
                )}
              </button>
            </div>
          </aside>

          <div className="fls-workspace-card">
            <div className="fls-channel-pane">
              <div className="fls-server-header">
                <div className="fls-server-header-badge">
                  {currentServer.shortLabel}
                </div>
                <div className="fls-server-header-copy">
                  <div className="fls-server-header-title">{serverTitle}</div>
                  <div className="fls-server-header-sub">
                    {currentServer.address}
                  </div>
                </div>
                <span className="fls-ping-chip" aria-hidden="true">
                  {currentServer.pingMs} ms
                </span>
              </div>

              <div className="fls-channel-tree">
                {groupedChannels.map(([groupLabel, channels]) => (
                  <div key={groupLabel} className="fls-channel-group">
                    <div className="fls-channel-group-header">
                      <svg
                        viewBox="0 0 16 16"
                        width="11"
                        height="11"
                        fill="none"
                        stroke="currentColor"
                        strokeWidth="2"
                        strokeLinecap="round"
                        aria-hidden="true"
                      >
                        <path d="M4 6l4 4 4-4" />
                      </svg>
                      <span>{groupLabel}</span>
                    </div>

                    {channels.map((ch) => {
                      const isSelected = ch.id === currentChannel.id;
                      const isVoiceRoom =
                        voiceConnected && ch.id === voiceChannelId;
                      const cName = locale === 'zh' ? ch.nameZh : ch.nameEn;

                      const treeMembers =
                        ch.id === currentChannel.id
                          ? effectiveMembers
                          : ch.members.filter((m) => m.id !== 'm-self');

                      return (
                        <div key={ch.id} className="fls-channel-branch">
                          <button
                            type="button"
                            className={`fls-channel-row ${isSelected ? 'is-selected' : ''} ${isVoiceRoom ? 'is-voice-active' : ''}`}
                            onClick={() => handleSelectChannel(ch)}
                          >
                            <span
                              className="fls-channel-row-icon"
                              aria-hidden="true"
                            >
                              {ch.icon === 'music' ? (
                                <svg
                                  viewBox="0 0 24 24"
                                  width="16"
                                  height="16"
                                  fill="none"
                                  stroke="currentColor"
                                  strokeWidth="2"
                                  strokeLinecap="round"
                                  strokeLinejoin="round"
                                >
                                  <path d="M9 18V5l12-2v13" />
                                  <circle cx="6" cy="18" r="3" />
                                  <circle cx="18" cy="16" r="3" />
                                </svg>
                              ) : ch.icon === 'shield' ? (
                                <svg
                                  viewBox="0 0 24 24"
                                  width="16"
                                  height="16"
                                  fill="none"
                                  stroke="currentColor"
                                  strokeWidth="2"
                                  strokeLinecap="round"
                                  strokeLinejoin="round"
                                >
                                  <path d="M12 22s8-4 8-10V5l-8-3-8 3v7c0 6 8 10 8 10z" />
                                </svg>
                              ) : (
                                <svg
                                  viewBox="0 0 24 24"
                                  width="16"
                                  height="16"
                                  fill="none"
                                  stroke="currentColor"
                                  strokeWidth="2"
                                  strokeLinecap="round"
                                  strokeLinejoin="round"
                                >
                                  <polygon points="11 5 6 9 2 9 2 15 6 15 11 19 11 5" />
                                  <path d="M15.54 8.46a5 5 0 0 1 0 7.07M19.07 4.93a10 10 0 0 1 0 14.14" />
                                </svg>
                              )}
                            </span>
                            <span className="fls-channel-row-name">{cName}</span>
                            {ch.locked && (
                              <span
                                className="fls-channel-lock"
                                aria-hidden="true"
                              >
                                <svg
                                  viewBox="0 0 24 24"
                                  width="12"
                                  height="12"
                                  fill="none"
                                  stroke="currentColor"
                                  strokeWidth="2"
                                >
                                  <rect
                                    x="4"
                                    y="11"
                                    width="16"
                                    height="10"
                                    rx="2"
                                  />
                                  <path d="M8 11V7a4 4 0 0 1 8 0v4" />
                                </svg>
                              </span>
                            )}
                            <span className="fls-channel-count">
                              {treeMembers.length}
                            </span>
                          </button>

                          {treeMembers.length > 0 && (
                            <div className="fls-tree-members">
                              {treeMembers.map((mem) => {
                                const isTalking =
                                  voiceConnected &&
                                  mem.speaking &&
                                  !mem.muted &&
                                  !mem.away;
                                return (
                                  <div
                                    key={mem.id}
                                    className={`fls-tree-member-row ${isTalking ? 'is-speaking' : ''}`}
                                  >
                                    <span
                                      className={`fls-tree-member-avatar ${isTalking ? 'is-speaking' : ''}`}
                                      style={{
                                        backgroundColor: mem.avatarColor,
                                      }}
                                    >
                                      {mem.name.slice(0, 2).toUpperCase()}
                                    </span>
                                    <span className="fls-tree-member-name">
                                      {mem.name}
                                    </span>
                                    <span className="fls-tree-member-state">
                                      {mem.muted ? (
                                        <svg
                                          viewBox="0 0 24 24"
                                          width="13"
                                          height="13"
                                          fill="none"
                                          stroke="currentColor"
                                          strokeWidth="2.1"
                                          className="fls-state-icon-error"
                                          aria-label={t(
                                            'previewMemberMicMuted'
                                          )}
                                        >
                                          <line
                                            x1="1"
                                            y1="1"
                                            x2="23"
                                            y2="23"
                                          />
                                          <path d="M9 9v3a3 3 0 0 0 5.12 2.12M15 9.34V4a3 3 0 0 0-5.94-.6" />
                                        </svg>
                                      ) : mem.away ? (
                                        <svg
                                          viewBox="0 0 24 24"
                                          width="13"
                                          height="13"
                                          fill="none"
                                          stroke="currentColor"
                                          strokeWidth="2"
                                          className="fls-state-icon-muted"
                                          aria-label={t('previewMemberAway')}
                                        >
                                          <circle cx="12" cy="12" r="9" />
                                          <path d="M12 7v5l3 2" />
                                        </svg>
                                      ) : isTalking ? (
                                        <span
                                          className="fls-mini-eq"
                                          aria-label={t(
                                            'previewMemberSpeaking'
                                          )}
                                        >
                                          <i />
                                          <i />
                                          <i />
                                        </span>
                                      ) : null}
                                    </span>
                                  </div>
                                );
                              })}
                            </div>
                          )}
                        </div>
                      );
                    })}
                  </div>
                ))}
              </div>

              <div className="fls-voice-dock">
                <div
                  className={`fls-voice-ribbon ${anySpeaking ? 'is-active' : ''} ${isMuted || !voiceConnected ? 'is-muted' : ''}`}
                >
                  <span className="fls-ribbon-icon" aria-hidden="true">
                    {isMuted || !voiceConnected ? (
                      <svg
                        viewBox="0 0 24 24"
                        width="13"
                        height="13"
                        fill="none"
                        stroke="currentColor"
                        strokeWidth="2.2"
                      >
                        <line x1="1" y1="1" x2="23" y2="23" />
                        <path d="M9 9v3a3 3 0 0 0 5.12 2.12M15 9.34V4a3 3 0 0 0-5.94-.6" />
                      </svg>
                    ) : (
                      <svg
                        viewBox="0 0 24 24"
                        width="13"
                        height="13"
                        fill="none"
                        stroke="currentColor"
                        strokeWidth="2.2"
                        strokeLinecap="round"
                      >
                        <path d="M4 10v4M8 7v10M12 4v16M16 8v8M20 10v4" />
                      </svg>
                    )}
                  </span>

                  <div className="fls-ribbon-bars" aria-hidden="true">
                    {Array.from({ length: BAR_COUNT }).map((_, idx) => {
                      let heightPct = 16;
                      if (voiceConnected && !isDeafened && anySpeaking) {
                        const wave =
                          Math.sin(idx * 0.45 + meterPhase * 0.35) * 0.5 + 0.5;
                        const env = Math.sin((idx / BAR_COUNT) * Math.PI);
                        heightPct = Math.round(18 + wave * env * 76);
                      }
                      return (
                        <span
                          key={idx}
                          className="fls-ribbon-bar"
                          style={{ height: `${heightPct}%` }}
                        />
                      );
                    })}
                  </div>

                  <span className="fls-ribbon-db">
                    {!voiceConnected
                      ? 'OFF'
                      : isDeafened
                        ? 'DEAF'
                        : isMuted
                          ? 'MUTE'
                          : anySpeaking
                            ? '-14 dB'
                            : '-54 dB'}
                  </span>
                </div>

                {voiceConnected ? (
                  <div className="fls-voice-status-bar">
                    <div className="fls-voice-status-info">
                      <div className="fls-voice-status-top">
                        <span
                          className="fls-voice-live-dot"
                          aria-hidden="true"
                        />
                        <span className="fls-voice-status-label">
                          {t('previewVoiceConnected')}
                        </span>
                      </div>
                      <div className="fls-voice-status-room">
                        {locale === 'zh'
                          ? activeVoiceChannel.nameZh
                          : activeVoiceChannel.nameEn}
                      </div>
                    </div>
                    <button
                      type="button"
                      className="fls-disconnect-btn"
                      onClick={() => setVoiceConnected(false)}
                      aria-label={t('previewDisconnect')}
                    >
                      <svg
                        viewBox="0 0 24 24"
                        width="15"
                        height="15"
                        fill="none"
                        stroke="currentColor"
                        strokeWidth="2.2"
                        strokeLinecap="round"
                        strokeLinejoin="round"
                      >
                        <path d="M10.68 13.31a16 16 0 0 0 3.41 2.6l1.27-1.27a2 2 0 0 1 2.11-.45c.907.339 1.85.573 2.81.7A2 2 0 0 1 22 16.92v3a2 2 0 0 1-2.18 2 19.79 19.79 0 0 1-8.63-3.07 19.42 19.42 0 0 1-3.33-2.67m-2.67-3.34a19.79 19.79 0 0 1-3.07-8.63A2 2 0 0 1 4.11 2h3a2 2 0 0 1 2 1.72c.127.96.361 1.903.7 2.81a2 2 0 0 1-.45 2.11L8.09 9.91" />
                        <line x1="22" y1="2" x2="2" y2="22" />
                      </svg>
                    </button>
                  </div>
                ) : (
                  <div className="fls-voice-status-bar is-disconnected">
                    <span className="fls-disconnected-text">
                      {t('previewDisconnectedHint')}
                    </span>
                    <button
                      type="button"
                      className="fls-reconnect-btn"
                      onClick={() => setVoiceConnected(true)}
                    >
                      {t('previewReconnectBtn')}
                    </button>
                  </div>
                )}

                <div className="fls-user-footer">
                  <div className="fls-self-profile">
                    <span
                      className={`fls-self-avatar ${voiceConnected && !isMuted && !isDeafened && !isAway ? 'is-speaking' : ''}`}
                    >
                      DR
                    </span>
                    <div className="fls-self-copy">
                      <span className="fls-self-name">Dr1mH4X</span>
                      <span className="fls-self-sub">
                        {isDeafened
                          ? t('previewDeafen')
                          : isMuted
                            ? t('previewMute')
                            : isAway
                              ? t('previewAway')
                              : 'Opus 48kHz'}
                      </span>
                    </div>
                  </div>

                  <div className="fls-user-controls">
                    <button
                      type="button"
                      className={`fls-ctrl-btn ${isMuted ? 'is-danger' : ''}`}
                      onClick={handleToggleMute}
                      aria-pressed={isMuted}
                      aria-label={
                        isMuted ? t('previewUnmute') : t('previewMute')
                      }
                    >
                      {isMuted ? (
                        <svg
                          viewBox="0 0 24 24"
                          width="16"
                          height="16"
                          fill="none"
                          stroke="currentColor"
                          strokeWidth="2.1"
                          strokeLinecap="round"
                        >
                          <line x1="1" y1="1" x2="23" y2="23" />
                          <path d="M9 9v3a3 3 0 0 0 5.12 2.12M15 9.34V4a3 3 0 0 0-5.94-.6" />
                          <path d="M17 16.95A7 7 0 0 1 5 12v-2m14 0v2a7 7 0 0 1-.11 1.23M12 19v4M8 23h8" />
                        </svg>
                      ) : (
                        <svg
                          viewBox="0 0 24 24"
                          width="16"
                          height="16"
                          fill="none"
                          stroke="currentColor"
                          strokeWidth="2"
                          strokeLinecap="round"
                        >
                          <rect x="9" y="2" width="6" height="11" rx="3" />
                          <path d="M19 10v2a7 7 0 0 1-14 0v-2M12 19v4M8 23h8" />
                        </svg>
                      )}
                    </button>

                    <button
                      type="button"
                      className={`fls-ctrl-btn ${isDeafened ? 'is-danger' : ''}`}
                      onClick={handleToggleDeafen}
                      aria-pressed={isDeafened}
                      aria-label={
                        isDeafened ? t('previewUndeafen') : t('previewDeafen')
                      }
                    >
                      {isDeafened ? (
                        <svg
                          viewBox="0 0 24 24"
                          width="16"
                          height="16"
                          fill="none"
                          stroke="currentColor"
                          strokeWidth="2.1"
                          strokeLinecap="round"
                        >
                          <line x1="2" y1="2" x2="22" y2="22" />
                          <path d="M3 14v-2a9 9 0 0 1 14.85-6.85M21 14v-2a8.96 8.96 0 0 0-1.15-4.38" />
                          <rect x="3" y="13" width="4" height="6" rx="1.5" />
                          <rect x="17" y="13" width="4" height="6" rx="1.5" />
                        </svg>
                      ) : (
                        <svg
                          viewBox="0 0 24 24"
                          width="16"
                          height="16"
                          fill="none"
                          stroke="currentColor"
                          strokeWidth="2"
                          strokeLinecap="round"
                        >
                          <path d="M3 18v-6a9 9 0 0 1 18 0v6" />
                          <path d="M21 19a2 2 0 0 1-2 2h-1a2 2 0 0 1-2-2v-3a2 2 0 0 1 2-2h3zM3 19a2 2 0 0 0 2 2h1a2 2 0 0 0 2-2v-3a2 2 0 0 0-2-2H3z" />
                        </svg>
                      )}
                    </button>

                    <button
                      type="button"
                      className={`fls-ctrl-btn ${isAway ? 'is-away' : ''}`}
                      onClick={handleToggleAway}
                      aria-pressed={isAway}
                      aria-label={
                        isAway ? t('previewUnaway') : t('previewAway')
                      }
                    >
                      <svg
                        viewBox="0 0 24 24"
                        width="16"
                        height="16"
                        fill="none"
                        stroke="currentColor"
                        strokeWidth="2"
                        strokeLinecap="round"
                      >
                        <circle cx="12" cy="12" r="9" />
                        <path d="M12 7v5l3 2" />
                      </svg>
                    </button>
                  </div>
                </div>
              </div>
            </div>

            <div className="fls-main-pane">
              <div className="fls-main-header">
                <div className="fls-main-title-group">
                  <span className="fls-main-hash" aria-hidden="true">
                    <svg
                      viewBox="0 0 24 24"
                      width="18"
                      height="18"
                      fill="none"
                      stroke="currentColor"
                      strokeWidth="2.1"
                      strokeLinecap="round"
                      strokeLinejoin="round"
                    >
                      <polygon points="11 5 6 9 2 9 2 15 6 15 11 19 11 5" />
                      <path d="M15.54 8.46a5 5 0 0 1 0 7.07" />
                    </svg>
                  </span>
                  <div className="fls-main-title-stack">
                    <span className="fls-main-channel-name">
                      {channelTitle}
                    </span>
                    <span className="fls-main-channel-topic">
                      {channelTopic}
                    </span>
                  </div>
                </div>

                <div className="fls-view-tabs" role="tablist">
                  {(
                    [
                      ['messages', 'previewTabMessages'],
                      ['media', 'previewTabMedia'],
                      ['files', 'previewTabFiles'],
                      ['details', 'previewTabDetails'],
                    ] as const
                  ).map(([tabId, labelKey]) => {
                    const isActive = activeTab === tabId;
                    return (
                      <button
                        key={tabId}
                        type="button"
                        role="tab"
                        aria-selected={isActive}
                        className={`fls-view-tab-btn ${isActive ? 'is-active' : ''}`}
                        onClick={() => setActiveTab(tabId)}
                      >
                        {t(labelKey)}
                      </button>
                    );
                  })}
                </div>
              </div>

              <div className="fls-main-body-split">
                <div className="fls-tab-viewport">
                  {transientNotice && (
                    <div className="fls-transient-notice" role="status">
                      <span className="fls-notice-dot" aria-hidden="true" />
                      <span>{transientNotice}</span>
                    </div>
                  )}

                  {activeTab === 'messages' && (
                    <div className="fls-chat-pane">
                      <div className="fls-chat-scroll">
                        <div className="fls-chat-welcome">
                          <div className="fls-chat-welcome-icon">
                            <svg
                              viewBox="0 0 24 24"
                              width="22"
                              height="22"
                              fill="none"
                              stroke="currentColor"
                              strokeWidth="2"
                              strokeLinecap="round"
                            >
                              <polygon points="11 5 6 9 2 9 2 15 6 15 11 19 11 5" />
                              <path d="M15.54 8.46a5 5 0 0 1 0 7.07M19.07 4.93a10 10 0 0 1 0 14.14" />
                            </svg>
                          </div>
                          <div>
                            <div className="fls-chat-welcome-title">
                              {t('previewWelcomeTitle', {
                                channel: channelTitle,
                              })}
                            </div>
                            <div className="fls-chat-welcome-sub">
                              {channelTopic}
                            </div>
                          </div>
                        </div>

                        <div className="fls-chat-messages">
                          {channelMessages.map((msg) => (
                            <div key={msg.id} className="fls-msg-row">
                              <span
                                className="fls-msg-avatar"
                                style={{ backgroundColor: msg.avatarColor }}
                              >
                                {msg.author.slice(0, 2).toUpperCase()}
                              </span>
                              <div className="fls-msg-body">
                                <div className="fls-msg-meta">
                                  <span className="fls-msg-author">
                                    {msg.author}
                                  </span>
                                  {msg.roleBadge && (
                                    <span className="fls-msg-badge">
                                      {msg.roleBadge}
                                    </span>
                                  )}
                                  <span className="fls-msg-time">
                                    {msg.time}
                                  </span>
                                </div>
                                <p className="fls-msg-text">
                                  {locale === 'zh' ? msg.textZh : msg.textEn}
                                </p>
                                {msg.codeSnippet && (
                                  <pre className="fls-msg-code">
                                    <code>{msg.codeSnippet}</code>
                                  </pre>
                                )}
                                {msg.attachmentTitle && (
                                  <div className="fls-msg-attachment">
                                    <div className="fls-attachment-wave" />
                                    <div className="fls-attachment-meta">
                                      <span className="fls-attachment-name">
                                        {msg.attachmentTitle}
                                      </span>
                                      <span className="fls-attachment-sub">
                                        {msg.attachmentMeta}
                                      </span>
                                    </div>
                                  </div>
                                )}
                              </div>
                            </div>
                          ))}
                        </div>
                      </div>

                      <form
                        className="fls-chat-composer"
                        onSubmit={handleSendMessage}
                      >
                        <input
                          type="text"
                          value={composerText}
                          onChange={(e) => setComposerText(e.target.value)}
                          placeholder={t('previewComposerHint', {
                            channel: channelTitle,
                          })}
                          aria-label={t('previewComposerHint', {
                            channel: channelTitle,
                          })}
                          className="fls-composer-input"
                        />
                        <button
                          type="submit"
                          className="fls-composer-send"
                          aria-label={t('previewSend')}
                        >
                          <svg
                            viewBox="0 0 24 24"
                            width="16"
                            height="16"
                            fill="none"
                            stroke="currentColor"
                            strokeWidth="2.2"
                            strokeLinecap="round"
                            strokeLinejoin="round"
                          >
                            <line x1="22" y1="2" x2="11" y2="13" />
                            <polygon points="22 2 15 22 11 13 2 9 22 2" />
                          </svg>
                        </button>
                      </form>
                    </div>
                  )}

                  {activeTab === 'media' && (
                    <div className="fls-media-pane">
                      <div className="fls-media-toolbar">
                        <div className="fls-scope-pills">
                          <button
                            type="button"
                            className={`fls-scope-pill ${mediaScope === 'channel' ? 'is-active' : ''}`}
                            onClick={() => setMediaScope('channel')}
                          >
                            {t('previewScopeChannel')}
                          </button>
                          <button
                            type="button"
                            className={`fls-scope-pill ${mediaScope === 'server' ? 'is-active' : ''}`}
                            onClick={() => setMediaScope('server')}
                          >
                            {t('previewScopeServer')}
                          </button>
                        </div>
                      </div>

                      <div className="fls-media-grid">
                        {MEDIA_ITEMS.filter(
                          (item) =>
                            mediaScope === 'server' ||
                            item.channelId === currentChannel.id ||
                            currentChannel.id === 'ch-duplex'
                        ).map((item) => (
                          <div key={item.id} className="fls-media-card">
                            <div
                              className="fls-media-thumb"
                              style={{ background: item.accent }}
                            >
                              <span className="fls-media-dims">
                                {item.dims}
                              </span>
                            </div>
                            <div className="fls-media-card-body">
                              <div className="fls-media-card-title">
                                {locale === 'zh' ? item.titleZh : item.titleEn}
                              </div>
                              <div className="fls-media-card-meta">
                                <span>@{item.sender}</span>
                                <span>{item.time}</span>
                              </div>
                            </div>
                          </div>
                        ))}
                      </div>
                    </div>
                  )}

                  {activeTab === 'files' && (
                    <div className="fls-files-pane">
                      <div className="fls-files-toolbar">
                        <span className="fls-files-path">
                          /{currentChannel.id}/artifacts
                        </span>
                        <span className="fls-files-count">
                          {currentChannel.files.length} items
                        </span>
                      </div>

                      <div className="fls-files-list">
                        {currentChannel.files.map((file) => (
                          <div key={file.name} className="fls-file-row">
                            <span
                              className="fls-file-icon"
                              aria-hidden="true"
                            >
                              {file.isDir ? (
                                <svg
                                  viewBox="0 0 24 24"
                                  width="17"
                                  height="17"
                                  fill="currentColor"
                                >
                                  <path d="M10 4H4a2 2 0 0 0-2 2v12a2 2 0 0 0 2 2h16a2 2 0 0 0 2-2V8a2 2 0 0 0-2-2h-8l-2-2z" />
                                </svg>
                              ) : (
                                <svg
                                  viewBox="0 0 24 24"
                                  width="17"
                                  height="17"
                                  fill="none"
                                  stroke="currentColor"
                                  strokeWidth="1.9"
                                >
                                  <path d="M14 2H6a2 2 0 0 0-2 2v16a2 2 0 0 0 2 2h12a2 2 0 0 0 2-2V8z" />
                                  <polyline points="14 2 14 8 20 8" />
                                </svg>
                              )}
                            </span>
                            <div className="fls-file-info">
                              <span className="fls-file-name">{file.name}</span>
                              <span className="fls-file-meta">
                                {file.size} · {file.updated}
                              </span>
                            </div>
                            {file.codecTag && (
                              <span className="fls-file-tag">
                                {file.codecTag}
                              </span>
                            )}
                            {!file.isDir && (
                              <button
                                type="button"
                                className="fls-file-dl-btn"
                                onClick={() =>
                                  setTransientNotice(
                                    t('previewFileSaved', { name: file.name })
                                  )
                                }
                                aria-label={`${t('previewFileDownload')} ${file.name}`}
                              >
                                <svg
                                  viewBox="0 0 24 24"
                                  width="15"
                                  height="15"
                                  fill="none"
                                  stroke="currentColor"
                                  strokeWidth="2.1"
                                  strokeLinecap="round"
                                >
                                  <path d="M21 15v4a2 2 0 0 1-2 2H5a2 2 0 0 1-2-2v-4M7 10l5 5 5-5M12 15V3" />
                                </svg>
                              </button>
                            )}
                          </div>
                        ))}
                      </div>
                    </div>
                  )}

                  {activeTab === 'details' && (
                    <div className="fls-details-pane">
                      <div className="fls-details-grid">
                        <div className="fls-detail-card">
                          <span className="fls-detail-label">AUDIO CODEC</span>
                          <span className="fls-detail-value">
                            {currentChannel.codec}
                          </span>
                        </div>
                        <div className="fls-detail-card">
                          <span className="fls-detail-label">
                            TARGET BITRATE
                          </span>
                          <span className="fls-detail-value">
                            {currentChannel.bitrate}
                          </span>
                        </div>
                        <div className="fls-detail-card">
                          <span className="fls-detail-label">
                            CONNECTION BOUNDARY
                          </span>
                          <span className="fls-detail-value">
                            Self-Hosted Direct ({currentServer.address})
                          </span>
                        </div>
                        <div className="fls-detail-card">
                          <span className="fls-detail-label">
                            SESSION ACTOR
                          </span>
                          <span className="fls-detail-value">
                            Single-Thread LocalSet · 0.0% Loss
                          </span>
                        </div>
                      </div>

                      <div className="fls-detail-desc-box">
                        <div className="fls-detail-desc-title">
                          {t('previewChannelDescTitle')}
                        </div>
                        <p className="fls-detail-desc-body">{channelTopic}</p>
                      </div>
                    </div>
                  )}
                </div>

                <aside className="fls-members-pane">
                  <div className="fls-members-header">
                    <span>{t('previewMembersTitle')}</span>
                    <span className="fls-members-badge">
                      {effectiveMembers.length}
                    </span>
                  </div>

                  <div className="fls-members-list">
                    {effectiveMembers.map((mem) => {
                      const isTalking =
                        voiceConnected &&
                        mem.speaking &&
                        !mem.muted &&
                        !mem.away;
                      return (
                        <div
                          key={mem.id}
                          className={`fls-member-card ${isTalking ? 'is-speaking' : ''}`}
                        >
                          <span
                            className={`fls-member-card-avatar ${isTalking ? 'is-speaking' : ''}`}
                            style={{ backgroundColor: mem.avatarColor }}
                          >
                            {mem.name.slice(0, 2).toUpperCase()}
                          </span>
                          <div className="fls-member-card-copy">
                            <span className="fls-member-card-name">
                              {mem.name}
                            </span>
                            <span className="fls-member-card-role">
                              {isTalking
                                ? t('previewMemberSpeaking')
                                : mem.away
                                  ? t('previewMemberAway')
                                  : mem.muted
                                    ? t('previewMemberMicMuted')
                                    : mem.role}
                            </span>
                          </div>
                          <span className="fls-member-ping">
                            {mem.pingMs} ms
                          </span>
                        </div>
                      );
                    })}
                  </div>
                </aside>
              </div>
            </div>
          </div>
        </div>
      </div>
    </div>
  );
};
