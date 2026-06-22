#include "cracker_core.h"
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <time.h>
#include <math.h>
#include <pthread.h>      // 使用 pthread-w32 或原生 pthread
#include <openssl/md5.h>
#include <openssl/sha.h>

/* ---------- 常量定义 ---------- */
#define MAX_HASH_LEN        128
#define MAX_PASS_LEN        128
#define PROGRESS_FILE       "cracker_progress.dat"

/* ---------- 全局配置 ---------- */
Config g_config = {
    .hash_type = HASH_MD5,
    .attack_mode = ATTACK_DICT,
    .theme = THEME_YIN_YANG_SHI,
    .dict_file = "",
    .hash_file = "",
    .output_file = "",
    .brute_max_len = 4,
    .brute_charset = "abcdefghijklmnopqrstuvwxyz0123456789",
    .resume = 0,
    .thread_count = 4,
    .show_progress = 1
};

/* ---------- 全局状态 ---------- */
HashNode* g_hash_list = NULL;
int g_total_hashes = 0;
int g_cracked_count = 0;
volatile int g_should_exit = 0;

pthread_mutex_t g_cracked_mutex = PTHREAD_MUTEX_INITIALIZER;

/* ---------- 暴力破解进度结构 ---------- */
typedef struct {
    int current_len;                // 当前尝试的长度
    long long tried_count;          // 已尝试的密码数
    long long total_count;          // 预估总密码数
    char current_pass[MAX_PASS_LEN];// 当前正在尝试的密码
} BruteProgress;

static BruteProgress g_brute_progress = {0};

/* ---------- 哈希计算实现 ---------- */
void compute_md5(const char* input, char* output) {
    unsigned char digest[MD5_DIGEST_LENGTH];
    MD5((unsigned char*)input, strlen(input), digest);
    for (int i = 0; i < MD5_DIGEST_LENGTH; i++)
        sprintf(output + i * 2, "%02x", digest[i]);
    output[MD5_DIGEST_LENGTH * 2] = '\0';
}

void compute_sha1(const char* input, char* output) {
    unsigned char digest[SHA_DIGEST_LENGTH];
    SHA1((unsigned char*)input, strlen(input), digest);
    for (int i = 0; i < SHA_DIGEST_LENGTH; i++)
        sprintf(output + i * 2, "%02x", digest[i]);
    output[SHA_DIGEST_LENGTH * 2] = '\0';
}

void compute_sha256(const char* input, char* output) {
    unsigned char digest[SHA256_DIGEST_LENGTH];
    SHA256((unsigned char*)input, strlen(input), digest);
    for (int i = 0; i < SHA256_DIGEST_LENGTH; i++)
        sprintf(output + i * 2, "%02x", digest[i]);
    output[SHA256_DIGEST_LENGTH * 2] = '\0';
}

void compute_hash(const char* password, char* hash_out) {
    switch (g_config.hash_type) {
    case HASH_MD5:    compute_md5(password, hash_out);    break;
    case HASH_SHA1:   compute_sha1(password, hash_out);   break;
    case HASH_SHA256: compute_sha256(password, hash_out); break;
    default:          compute_md5(password, hash_out);
    }
}

/* ---------- 加载哈希文件 ---------- */
void load_hashes(const char* filename) {
    FILE* fp = fopen(filename, "r");
    if (!fp) return;
    char line[MAX_HASH_LEN];
    while (fgets(line, sizeof(line), fp)) {
        line[strcspn(line, "\n")] = '\0';
        if (strlen(line) == 0) continue;
        HashNode* node = (HashNode*)malloc(sizeof(HashNode));
        strcpy(node->hash, line);
        node->plain[0] = '\0';
        node->next = g_hash_list;
        g_hash_list = node;
        g_total_hashes++;
    }
    fclose(fp);
}

/* ---------- 检查并记录破解结果 ---------- */
int check_and_record(const char* password) {
    char hash[MAX_HASH_LEN];
    compute_hash(password, hash);
    int found = 0;
    pthread_mutex_lock(&g_cracked_mutex);
    for (HashNode* node = g_hash_list; node; node = node->next) {
        if (node->plain[0] == '\0' && strcmp(node->hash, hash) == 0) {
            strcpy(node->plain, password);
            g_cracked_count++;
            found = 1;
        }
    }
    pthread_mutex_unlock(&g_cracked_mutex);
    return found;
}

/* ---------- 保存结果 ---------- */
void save_results(void) {
    if (strlen(g_config.output_file) == 0) return;
    FILE* fp = fopen(g_config.output_file, "w");
    if (!fp) return;
    for (HashNode* node = g_hash_list; node; node = node->next) {
        fprintf(fp, "%s:%s\n", node->hash, node->plain[0] ? node->plain : "?");
    }
    fclose(fp);
}

/* ---------- 字典攻击 ---------- */
void dict_attack(void) {
    FILE* fp = fopen(g_config.dict_file, "r");
    if (!fp) return;
    char line[MAX_PASS_LEN];
    while (fgets(line, sizeof(line), fp) && !g_should_exit) {
        line[strcspn(line, "\n")] = '\0';
        check_and_record(line);
        if (g_cracked_count == g_total_hashes) break;
    }
    fclose(fp);
}

/* ---------- 雷索纳斯弱密码字典 ---------- */
static const char* weak_passwords[] = {
    "123456", "password", "12345678", "qwerty", "12345", "admin",
    "welcome", "123456789", "1234", "1234567", "123123", "000000",
    "111111", "abc123", "123", "1q2w3e", "iloveyou", "sunshine", NULL
};

void reso_dict_attack(void) {
    for (int i = 0; weak_passwords[i] && !g_should_exit; i++) {
        check_and_record(weak_passwords[i]);
        if (g_cracked_count == g_total_hashes) return;
    }
    dict_attack();  // 接着进行标准字典攻击
}

/* ================================================================
 * 暴力破解辅助函数
 * ================================================================ */

// 计算指定长度下所有密码组合总数
static long long calc_total_combinations(int max_len, const char* charset) {
    int cs_len = (int)strlen(charset);
    long long total = 0;
    long long cur = 1;
    for (int i = 1; i <= max_len; i++) {
        cur *= cs_len;
        total += cur;
    }
    return total;
}

// 将数字索引转换为对应密码字符串（类似进制转换）
static void index_to_password(long long idx, int length, const char* charset, char* out) {
    int cs_len = (int)strlen(charset);
    for (int i = length - 1; i >= 0; i--) {
        out[i] = charset[idx % cs_len];
        idx /= cs_len;
    }
    out[length] = '\0';
}

/* ---------- 暴力破解（单线程，无断点续破） ---------- */
void brute_attack_single(void) {
    int cs_len = (int)strlen(g_config.brute_charset);
    int max_len = g_config.brute_max_len;
    long long total_count = calc_total_combinations(max_len, g_config.brute_charset);
    long long tried = 0;

    // 逐长度尝试
    for (int len = 1; len <= max_len && !g_should_exit; len++) {
        long long count_for_len = (long long)pow(cs_len, len);
        char* password = (char*)malloc(len + 1);

        for (long long i = 0; i < count_for_len && !g_should_exit; i++) {
            index_to_password(i, len, g_config.brute_charset, password);
            if (check_and_record(password)) {
                if (g_cracked_count == g_total_hashes) {
                    free(password);
                    return;
                }
            }
            tried++;
            if (g_config.show_progress && tried % 10000 == 0) {
                printf("\rProgress: %.2f%%", (tried * 100.0) / total_count);
                fflush(stdout);
            }
        }
        free(password);
    }
}

/* ---------- 多线程暴力破解参数结构 ---------- */
typedef struct {
    int thread_id;
    long long start_idx;
    long long end_idx;
    int length;
} ThreadArg;

static pthread_mutex_t progress_mutex = PTHREAD_MUTEX_INITIALIZER;
static long long global_tried = 0;
static long long global_total = 0;

// 多线程工作函数：处理指定长度下的一个密码段
static void* brute_thread_worker(void* arg) {
    ThreadArg* targ = (ThreadArg*)arg;
    int cs_len = (int)strlen(g_config.brute_charset);
    char* password = (char*)malloc(targ->length + 1);

    for (long long i = targ->start_idx; i < targ->end_idx && !g_should_exit; i++) {
        index_to_password(i, targ->length, g_config.brute_charset, password);
        if (check_and_record(password)) {
            if (g_cracked_count == g_total_hashes) {
                free(password);
                return NULL;
            }
        }

        // 更新全局进度（线程安全）
        pthread_mutex_lock(&progress_mutex);
        global_tried++;
        if (g_config.show_progress && global_tried % 5000 == 0) {
            printf("\rProgress: %.2f%%", (global_tried * 100.0) / global_total);
            fflush(stdout);
        }
        pthread_mutex_unlock(&progress_mutex);
    }
    free(password);
    return NULL;
}

/* ---------- 暴力破解（多线程，无断点续破） ---------- */
void brute_attack_multi(void) {
    int cs_len = (int)strlen(g_config.brute_charset);
    int max_len = g_config.brute_max_len;
    int num_threads = g_config.thread_count;
    if (num_threads <= 0) num_threads = 4;

    global_total = calc_total_combinations(max_len, g_config.brute_charset);
    global_tried = 0;

    pthread_t* threads = (pthread_t*)malloc(sizeof(pthread_t) * num_threads);
    ThreadArg* args = (ThreadArg*)malloc(sizeof(ThreadArg) * num_threads);

    // 逐长度破解
    for (int len = 1; len <= max_len && !g_should_exit; len++) {
        long long total_for_len = (long long)pow(cs_len, len);
        long long chunk_size = total_for_len / num_threads;
        if (chunk_size < 1) chunk_size = 1;

        // 创建线程
        for (int t = 0; t < num_threads; t++) {
            args[t].thread_id = t;
            args[t].length = len;
            args[t].start_idx = t * chunk_size;
            args[t].end_idx = (t == num_threads - 1) ? total_for_len : (t + 1) * chunk_size;
            pthread_create(&threads[t], NULL, brute_thread_worker, &args[t]);
        }

        // 等待所有线程结束
        for (int t = 0; t < num_threads; t++) {
            pthread_join(threads[t], NULL);
        }
        if (g_cracked_count == g_total_hashes) break;
    }

    free(threads);
    free(args);
}

/* ---------- 断点续破支持 ---------- */

// 保存当前暴力破解进度到文件
static void save_progress(void) {
    FILE* fp = fopen(PROGRESS_FILE, "wb");
    if (!fp) return;
    fwrite(&g_brute_progress, sizeof(BruteProgress), 1, fp);
    fclose(fp);
}

// 加载进度文件，成功返回1，失败返回0
static int load_progress(void) {
    FILE* fp = fopen(PROGRESS_FILE, "rb");
    if (!fp) return 0;
    size_t n = fread(&g_brute_progress, sizeof(BruteProgress), 1, fp);
    fclose(fp);
    return (n == 1);
}

// 递归生成密码的核心函数（用于断点续破场景）
static int brute_recursive(char* current, int pos, int max_len, const char* charset, int cs_len, long long* tried) {
    if (g_should_exit || g_cracked_count == g_total_hashes) return 1;

    // 如果不是第一次调用（pos>0）且长度>=1，检查当前密码
    if (pos > 0) {
        current[pos] = '\0';
        // 检查是否应该从恢复点开始（仅当恢复模式下且未开始处理时）
        if (g_config.resume) {
            static int resumed = 0;
            if (!resumed) {
                // 比较当前密码与保存的进度密码，跳过已经尝试过的
                if (strcmp(current, g_brute_progress.current_pass) < 0) {
                    (*tried)++;
                    return 0;  // 跳过
                }
                resumed = 1;
            }
        }
        if (check_and_record(current)) {
            if (g_cracked_count == g_total_hashes) return 1;
        }
        (*tried)++;
        // 更新进度信息（每1000次保存一次，避免频繁IO）
        if (g_config.resume && (*tried) % 1000 == 0) {
            strcpy(g_brute_progress.current_pass, current);
            g_brute_progress.tried_count = *tried;
            g_brute_progress.current_len = pos;
            save_progress();
        }
    }

    // 达到最大长度则返回
    if (pos >= max_len) return 0;

    // 递归生成下一个字符
    for (int i = 0; i < cs_len; i++) {
        current[pos] = charset[i];
        if (brute_recursive(current, pos + 1, max_len, charset, cs_len, tried))
            return 1;
        if (g_should_exit) return 1;
    }
    return 0;
}

/* ---------- 暴力破解（支持断点续破） ---------- */
void brute_attack_resumable(void) {
    int cs_len = (int)strlen(g_config.brute_charset);
    int max_len = g_config.brute_max_len;
    char current[MAX_PASS_LEN] = {0};
    long long tried = 0;
    long long total = calc_total_combinations(max_len, g_config.brute_charset);

    // 如果是恢复模式，尝试加载进度
    if (g_config.resume) {
        if (load_progress()) {
            tried = g_brute_progress.tried_count;
            strcpy(current, g_brute_progress.current_pass);
            printf("Resuming from length %d, password: %s\n", g_brute_progress.current_len, current);
        } else {
            // 无进度文件，创建新的
            g_brute_progress.current_len = 0;
            g_brute_progress.tried_count = 0;
            g_brute_progress.total_count = total;
            strcpy(g_brute_progress.current_pass, "");
            save_progress();
        }
    } else {
        // 非恢复模式，删除旧的进度文件（如果存在）
        remove(PROGRESS_FILE);
    }

    // 开始递归生成并尝试密码
    brute_recursive(current, 0, max_len, g_config.brute_charset, cs_len, &tried);

    // 完成后删除进度文件
    if (!g_should_exit) {
        remove(PROGRESS_FILE);
    }
}

/* ---------- 主调度函数 ---------- */
void run_cracker(void) {
    // 初始化：加载哈希文件
    if (strlen(g_config.hash_file) > 0) {
        load_hashes(g_config.hash_file);
    }

    // 根据攻击模式选择破解方法
    if (g_config.attack_mode == ATTACK_DICT) {
        if (g_config.theme == THEME_RESO_NANCE)
            reso_dict_attack();
        else
            dict_attack();
    } else {
        // 暴力破解模式，根据主题选择不同的实现
        if (g_config.theme == THEME_DEEP_SPACE)
            brute_attack_multi();
        else if (g_config.theme == THEME_REVERSE_1999)
            brute_attack_resumable();
        else
            brute_attack_single();
    }

    // 保存破解结果
    save_results();
}
