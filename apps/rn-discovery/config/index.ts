/**
 * 环境配置 — 控制 mock / 真实 API 切换。
 *
 * 后续接入 Apple Music API 时，只需：
 *   1. 将 USE_MOCK 改为 false
 *   2. 实现 stationService.ts 中的 fetchStations() 等函数
 *   3. 其余代码无需改动
 */
export const Config = {
  /** 是否使用 mock 数据 */
  USE_MOCK: true,

  /** API base URL（接入真实后端时替换） */
  API_BASE_URL: 'https://api.example.com/v1',

  /** Apple Music 开发者 token 获取地址 */
  APPLE_MUSIC_TOKEN_URL: 'https://api.example.com/auth/apple-music',
} as const;
