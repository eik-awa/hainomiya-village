//
//  LevelPlayConfig.swift
//  hainomiya-village
//

import Foundation

enum LevelPlayConfig {
    // TODO: Unity LevelPlay ダッシュボードで発行された App Key に置き換える
    static let appKey = "27a85032d"
    // TODO: バナー広告のプレースメント(Ad Unit)ID に置き換える
    static let bannerAdUnitID = "920bvvazubr4dewz"
    // 検索結果ページ内の大きめバナー(300x250)用。バナーと同じ Ad Unit を使う。
    // MREC 用に別の Ad Unit を発行した場合はここを置き換える。
    static let inlineAdUnitID = bannerAdUnitID
    // ヒント解放用リワード広告のプレースメント(Ad Unit)ID
    static let rewardedAdUnitID = "zh8sga6lcs1o7njb"
}
