#ifndef CMULTITOUCH_H
#define CMULTITOUCH_H

#include <stdbool.h>
#include <stdint.h>

// MultitouchSupport.framework（非公開）の接触点。レイアウトは 96 バイトで、
// MiddleClick や OpenMultitouchSupport などが使っている定義と同じ（macOS 26.6 / M4 で確認済み）。
typedef struct {
    float x;
    float y;
} CMTPoint;

typedef struct {
    CMTPoint position;
    CMTPoint velocity;
} CMTVector;

typedef struct {
    int32_t frame;
    double timestamp;
    int32_t identifier;
    int32_t state;      // 1-2: 近接, 3: 接触開始, 4: 接触中, 5: 離れる, 6-7: 範囲外
    int32_t fingerID;
    int32_t handID;
    CMTVector normalized; // 0〜1。y は手前が 0
    float zTotal;
    int32_t field9;
    float angle;
    float majorAxis;
    float minorAxis;
    CMTVector absolute;   // mm
    int32_t field14;
    int32_t field15;
    float zDensity;
} CMTTouch;

typedef struct {
    // MTDeviceGetDeviceID。IOKit の "Multitouch ID" と同じ値で、抜き差ししても変わらない
    uint64_t deviceID;
    int32_t familyID;
    bool builtIn;
    // 単位は 0.01mm。取れなければ 0
    int32_t surfaceWidth;
    int32_t surfaceHeight;
} CMTDeviceInfo;

// MultitouchSupport のスレッドで呼ばれる。touches は呼び出しの間だけ有効。
typedef void (*CMTFrameHandler)(void *context, uint64_t deviceID, const CMTTouch *touches, int32_t count, double timestamp);

// フレームワークを読み込む。何度呼んでもよい。失敗したら err に理由を書いて false。
bool cmt_load(char *err, int32_t errlen);

// いまつながっているデバイスを調べる（開始はしない）。out には capacity 台まで書き、戻り値は全体の台数。
// 読み込む前なら -1。
int32_t cmt_list_devices(CMTDeviceInfo *out, int32_t capacity);

// デバイスの一覧を作り直し、deviceIDs にあるデバイスだけを開始して handler にフレームを流す。
// 動いていれば先に止める。開始できたデバイスの ID を startedIDs（idCount 個まで）に書き、その数を返す。
// cmt_start / cmt_stop は同じスレッド（メインスレッド）から呼ぶ。
int32_t cmt_start(const uint64_t *deviceIDs, int32_t idCount, CMTFrameHandler handler, void *context, uint64_t *startedIDs);

// コールバックを外してデバイスを止める。戻った後は handler も context も使われない。
void cmt_stop(void);

// 触覚（Force Touch のアクチュエータ）。戻り値は IOReturn（0 で成功）、使えなければ -1。メインスレッドから呼ぶ。
int32_t cmt_actuator_open(uint64_t deviceID);
int32_t cmt_actuator_actuate(int32_t actuationID, uint32_t unknown1, float unknown2, float unknown3);
void cmt_actuator_close(void);

#endif
