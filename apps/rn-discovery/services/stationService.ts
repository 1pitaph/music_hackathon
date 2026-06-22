/**
 * 电台数据服务层 — 统一数据存取入口。
 *
 * 上层组件只调用这个模块的函数，不直接读写 data/ 下的文件。
 * 切换 mock / 真实 API 只需改 config/index.ts 中的 USE_MOCK。
 */

import { Config } from '@/config';
import { stations as mockStations } from '@/data/stations';
import { popularStationIds } from '@/data/trending';
import { Station } from '@/types/station';

// ─── 接口定义（与 types/station.ts 保持一致） ───

export interface FetchStationsResult {
  stations: Station[];
  /** 热门电台 ID 列表（按收藏量降序） */
  popularIds: string[];
  /** 随机推荐电台 ID 列表（供卡片区使用） */
  randomIds: string[];
}

export interface FetchError {
  code: 'NETWORK' | 'AUTH' | 'UNKNOWN';
  message: string;
}

// ─── Mock 实现 ───

async function fetchMockStations(): Promise<FetchStationsResult> {
  // 模拟网络延迟
  await new Promise((r) => setTimeout(r, 400));

  return {
    stations: mockStations,
    popularIds: popularStationIds,
    randomIds: [...popularStationIds].sort(() => Math.random() - 0.5).slice(0, 4),
  };
}

// ─── 真实 API 实现（接入时在此填充） ───

async function fetchRealStations(): Promise<FetchStationsResult> {
  // TODO: 接入 Apple Music API + 后端电台 Agent
  //
  // 预期流程：
  //   1. 获取 Apple Music developer token
  //   2. 调用 /v1/stations?userId={userId} 获取用户专属电台列表
  //   3. 返回 FetchStationsResult 格式
  //
  // 示例骨架：
  //
  //   const token = await getAppleMusicToken();
  //   const res = await fetch(`${Config.API_BASE_URL}/stations`, {
  //     headers: { Authorization: `Bearer ${token}` },
  //   });
  //   if (!res.ok) throw { code: 'NETWORK', message: res.statusText };
  //   const data = await res.json();
  //   return {
  //     stations: data.stations,
  //     popularIds: data.popularIds,
  //     randomIds: data.randomIds,
  //   };

  throw { code: 'UNKNOWN', message: 'Real API not implemented yet' } as FetchError;
}

// ─── 统一入口 ───

/**
 * 获取所有电台数据（卡片区 + 热门列表）。
 *
 * 上层只需要 `import { loadStations } from '@/services/stationService'`
 * 然后 `await loadStations()` 即可拿到数据，不关心是 mock 还是真实 API。
 */
export async function loadStations(): Promise<FetchStationsResult> {
  if (Config.USE_MOCK) {
    return fetchMockStations();
  }
  return fetchRealStations();
}

// ─── 后续可扩展的接口 ───

/**
 * 获取某个电台的详情（含歌曲列表）。
 * 当前直接返回 mock 数据，接入时改为 API 调用。
 */
export async function loadStationDetail(stationId: string): Promise<Station | null> {
  if (Config.USE_MOCK) {
    return mockStations.find((s) => s.id === stationId) ?? null;
  }
  // TODO: GET /v1/stations/:id
  return null;
}

/**
 * 收藏/取消收藏电台。
 * mock 模式下仅打印日志。
 */
export async function toggleFavoriteStation(
  stationId: string,
  favorited: boolean,
): Promise<void> {
  if (Config.USE_MOCK) {
    console.log(`[mock] ${favorited ? '收藏' : '取消收藏'} 电台: ${stationId}`);
    return;
  }
  // TODO: POST /v1/stations/:id/favorite
}
