/* coil-time C ABI — chrono + Instant registry, loaded via dload("time"). */
#ifndef COIL_TIME_H
#define COIL_TIME_H

#include <stdint.h>

#ifdef __cplusplus
extern "C" {
#endif

/* Error tags written to err_out / last_error (TimeError wire order). */
#define COIL_TIME_ERR_INVALID_INPUT 0
#define COIL_TIME_ERR_OVERFLOW 1
#define COIL_TIME_ERR_PARSE_ERROR 2
#define COIL_TIME_ERR_OTHER 3

/* Return: 0 on success, -1 on error (err_out / last_error set). */
int64_t coil_time_timestamp(int64_t *err_out);
int64_t coil_time_sleep_ms(int64_t millis, int64_t *err_out);
int64_t coil_time_instant_now(int64_t *err_out);
int64_t coil_time_instant_drop(int64_t handle, int64_t *err_out);
int64_t coil_time_elapsed_nanos(int64_t handle, int64_t *err_out);
int64_t coil_time_elapsed_millis(int64_t handle, int64_t *err_out);
int64_t coil_time_period(
    int64_t years, int64_t months, int64_t days, int64_t hours, int64_t minutes,
    int64_t secs, int64_t millis, int64_t micros, int64_t nanos, int64_t *err_out);
int64_t coil_time_add(int64_t ts_nanos, int64_t *err_out);
int64_t coil_time_sub(int64_t ts_nanos, int64_t *err_out);
int64_t coil_time_period_add(int64_t *err_out);
int64_t coil_time_period_sub(int64_t *err_out);
int64_t coil_time_date(int64_t *err_out);
int64_t coil_time_date_from_period(int64_t *err_out);
int64_t coil_time_date_from_epoch_period(int64_t *err_out);
int64_t coil_time_epoch(int64_t *err_out);
int64_t coil_time_format_hold(const uint8_t *fmt, uint64_t fmt_len, uint8_t *out, uint64_t out_len);
int64_t coil_time_format_apply(int64_t ts_nanos, int64_t *err_out);
int64_t coil_time_format(int64_t ts_nanos, const uint8_t *fmt, uint64_t fmt_len, uint8_t *out, uint64_t out_len, int64_t *err_out);
int64_t coil_time_parse(const uint8_t *text, uint64_t text_len, const uint8_t *fmt, uint64_t fmt_len, int64_t *err_out);

/* Period in/out: 9 i64 fields (years … nanos). Timestamp in/out: field 0 unused for
 * add/sub (ts_nanos arg); after success, fields 0..3 are secs/millis/micros/nanos. */
int64_t coil_time_store_i64(int64_t i, int64_t v);
int64_t coil_time_field(int64_t i);

uint8_t *coil_time_null(void);
int64_t coil_time_last_error(void);
int64_t coil_time_last_i64(void);
uint8_t *coil_time_alloc(uint64_t n);
void coil_time_free(uint8_t *ptr, uint64_t n);
void coil_time_store_u8(uint8_t *ptr, uint64_t i, int64_t v);
int64_t coil_time_load_u8(const uint8_t *ptr, uint64_t i);

#ifdef __cplusplus
}
#endif

#endif
