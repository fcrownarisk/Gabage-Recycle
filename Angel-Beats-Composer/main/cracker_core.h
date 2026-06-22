#ifndef CRACKER_CORE_H
#define CRACKER_CORE_H

#include <windows.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <openssl/md5.h>
#include <openssl/sha.h>

#define MAX_HASH_LEN 128
#define MAX_PASS_LEN 64

typedef enum {
    HASH_MD5,
    HASH_SHA1,
    HASH_SHA256
} HashType;

typedef enum {
    ATTACK_DICT,
    ATTACK_BRUTE
} AttackMode;

typedef enum {
    THEME_YIN_YANG_SHI,
    THEME_DEEP_SPACE,
    THEME_REVERSE_1999,
    THEME_RESO_NANCE
} Theme;

typedef struct {
    HashType   hash_type;
    AttackMode attack_mode;
    Theme      theme;
    char       dict_file[MAX_PATH];
    char       hash_file[MAX_PATH];
    char       output_file[MAX_PATH];
    int        brute_max_len;
    char       brute_charset[96];
    int        resume;
    int        thread_count;
    int        show_progress;
} Config;

typedef struct {
    char hash[MAX_HASH_LEN];
    char plain[MAX_PASS_LEN];
    struct HashNode* next;
} HashNode;

// 全局状态（供GUI回调查询）
extern Config g_config;
extern HashNode* g_hash_list;
extern int g_total_hashes;
extern int g_cracked_count;
extern volatile int g_should_exit;

// 函数声明
void load_hashes(const char* filename);
void compute_hash(const char* password, char* hash_out);
int check_and_record(const char* password);
void dict_attack(void);
void reso_dict_attack(void);
void brute_attack_single(void);
void brute_attack_multi(void);
void brute_attack_resumable(void);
void run_cracker(void);
void save_results(void);
long long count_combinations(int max_len, int charset_len);

#endif