#ifndef CMULTITOUCH_H
#define CMULTITOUCH_H

#include <stdbool.h>
#include <stdint.h>

// MultitouchSupport.framework（非公開）の接触点。レイアウトは 96 バイトで、
// MiddleClick や OpenMultitouchSupport などが使っている定義と同じ。
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

// deviceIndex は cmt_device_count() の添字。見つからなければ -1。
typedef void (*CMTFrameHandler)(int32_t deviceIndex, const CMTTouch *touches, int32_t count, double timestamp);

// フレームワークを読み込み、デバイス一覧を作る。失敗したら err に理由を書いて false。
bool cmt_load(char *err, int32_t errlen);

int32_t cmt_device_count(void);
bool cmt_device_is_builtin(int32_t index);
int32_t cmt_device_family_id(int32_t index);
uint64_t cmt_device_id(int32_t index);
// 単位は 0.01mm
bool cmt_device_surface_size(int32_t index, int32_t *width, int32_t *height);

// 全デバイスの接触フレームを handler に流す。handler は MultitouchSupport のスレッドで呼ばれる。
void cmt_start(CMTFrameHandler handler);
void cmt_stop(void);

// 触覚（Force Touch のアクチュエータ）。戻り値は IOReturn（0 で成功）、アクチュエータが無ければ -1。
int32_t cmt_actuator_open(int32_t deviceIndex);
int32_t cmt_actuator_actuate(int32_t actuationID, uint32_t unknown1, float unknown2, float unknown3);
void cmt_actuator_close(void);

#endif
