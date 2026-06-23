/**
 * Music Service — 数据获取层
 *
 * 所有数据获取操作统一封装在这里，目前使用 mockData 提供假数据，
 * 后续接入真实 Apple Music API 时只需替换各个函数内部的实现。
 *
 * ============================================================================
 * Apple Music API 端点映射（供队友参考，切换真实数据时使用）
 * ============================================================================
 *
 * getUserProfile()
 *   Mock: 返回 mockUserProfile
 *   Apple Music API:
 *     - 用户昵称/头像 → 需自建用户系统存储，Apple Music API 不提供用户 profile 字段
 *     - 统计数据（时长、电台数）→ 自建后端 /stats 端点聚合
 *     - nowPlaying → Apple Music API: GET /v1/me/recent/played?limit=1
 *
 * getPublishedStations()
 *   Mock: 返回 mockUserProfile.published
 *   真实来源:
 *     - 用户自建电台 → 自建后端 /api/stations?type=published
 *     - Apple Music 播放列表 → GET /v1/me/library/playlists
 *
 * getSavedStations()
 *   Mock: 返回 mockUserProfile.saved
 *   真实来源:
 *     - 用户收藏 → 自建后端 /api/stations?type=saved
 *     - Apple Music 收藏 → GET /v1/me/library/playlists (filter: saved)
 *
 * getRecentlyPlayed()
 *   Mock: 返回 mockUserProfile.recentlyPlayed
 *   Apple Music API: GET /v1/me/recent/played
 *
 * getArtists()
 *   Mock: 返回 mockUserProfile.artists
 *   真实来源:
 *     - 从用户电台中聚合出现过的艺人 → 自建后端 /api/artists
 *     - Apple Music 常听艺人 → GET /v1/me/recent/played 中聚合 artistName
 *
 * ============================================================================
 * 认证说明
 * ============================================================================
 *
 * Apple Music API 需要两类 token：
 *   1. Developer Token (JWT) — 服务端生成，用 Apple Music Kit 私钥签名
 *   2. Music User Token — 用户授权后由 MusicKit 返回，用于访问用户个人数据
 *
 * 自建后端 API 使用标准的 Bearer token 认证。
 *
 * 切换真实数据时，在函数内部：
 *   1. 调用 fetch() 请求对应端点
 *   2. 处理 HTTP 错误并抛出有意义的错误信息
 *   3. 将 API 返回的 JSON 映射为现有的 StationItem / UserProfile 类型
 */

import { mockUserProfile, UserProfile, StationItem } from '../data/mockData';

// ====== 模拟网络延迟（方便后续测试 loading 状态） ======
const MOCK_DELAY_MS = 0; // 设为 500 可模拟网络延迟

function simulateDelay(): Promise<void> {
  if (MOCK_DELAY_MS <= 0) return Promise.resolve();
  return new Promise((resolve) => setTimeout(resolve, MOCK_DELAY_MS));
}

// ====== Service Functions ======

/**
 * 获取用户基本信息
 *
 * @returns 用户昵称、头像、统计数据、nowPlaying 等完整信息
 *
 * 真实 API: 自建后端 GET /api/profile + Apple Music GET /v1/me/recent/played?limit=1
 */
export async function getUserProfile(): Promise<UserProfile> {
  await simulateDelay();
  return { ...mockUserProfile };
}

/**
 * 获取已发布的电台列表
 *
 * @returns 用户自建/发布的电台列表
 *
 * 真实 API: 自建后端 GET /api/stations?type=published
 *           或 Apple Music GET /v1/me/library/playlists
 */
export async function getPublishedStations(): Promise<StationItem[]> {
  await simulateDelay();
  return [...mockUserProfile.published];
}

/**
 * 获取已收藏的电台列表
 *
 * @returns 用户收藏的电台列表
 *
 * 真实 API: 自建后端 GET /api/stations?type=saved
 *           或 Apple Music GET /v1/me/library/playlists (filter: saved)
 */
export async function getSavedStations(): Promise<StationItem[]> {
  await simulateDelay();
  return [...mockUserProfile.saved];
}

/**
 * 获取最近播放记录
 *
 * @returns 最近播放的电台列表
 *
 * 真实 API: Apple Music GET /v1/me/recent/played
 */
export async function getRecentlyPlayed(): Promise<StationItem[]> {
  await simulateDelay();
  return [...mockUserProfile.recentlyPlayed];
}

/**
 * 获取出现过的歌手列表
 *
 * @returns 歌手名称数组
 *
 * 真实 API: 自建后端 GET /api/artists
 *           或从 Apple Music GET /v1/me/recent/played 中聚合 artistName
 */
export async function getArtists(): Promise<string[]> {
  await simulateDelay();
  return [...mockUserProfile.artists];
}
