/**
 * hashcracker.c
 * 主题化哈希破解工具：融合阴阳师、深空之眼、重返未来1999、雷索纳斯
 * 改进版：高可读性、模块化、丰富功能
 * 
 * 编译: gcc -o hashcracker hashcracker.c -lcrypto -lpthread -O2 -Wall
 */

#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <ctype.h>
#include <pthread.h>
#include <unistd.h>
#include <time.h>
#include <signal.h>
#include <math.h>
#include <openssl/md5.h>
#include <openssl/sha.h>

/* ------------------------------- 常量定义 --------------------------------- */
#define MAX_HASH_LEN         128     // 十六进制哈希字符串最大长度（SHA256为64）
#define MAX_PASS_LEN         64      // 密码最大长度
#define MAX_LINE_LEN         256
#define PROGRESS_FILE        "cracker_progress.bin"
#define DEFAULT_THREAD_COUNT 4       // 默认线程数（深空之眼可自动检测）
#define PROGRESS_UPDATE_INTERVAL 10000  // 每尝试多少次更新一次进度显示

/* 哈希类型枚举 */
typedef enum {
    HASH_MD5,
    HASH_SHA1,
    HASH_SHA256
} HashType;

/* 攻击模式枚举 */
typedef enum {
    ATTACK_DICT,
    ATTACK_BRUTE
} AttackMode;

/* 游戏主题枚举 */
typedef enum {
    THEME_YIN_YANG_SHI,   // 阴阳师 - 节能单线程
    THEME_DEEP_SPACE,     // 深空之眼 - 多线程战斗
    THEME_REVERSE_1999,   // 重返未来 - 断点续传
    THEME_RESO_NANCE      // 雷索纳斯 - 频率共振
} Theme;

/* ------------------------------- 全局配置结构 ----------------------------- */
typedef struct {
    HashType   hash_type;
    AttackMode attack_mode;
    Theme      theme;
    char       dict_file[256];      // 字典文件路径
    char       hash_file[256];      // 目标哈希文件路径
    char       output_file[256];    // 结果输出文件（可选）
    int        brute_max_len;       // 暴力破解最大长度
    char       brute_charset[96];   // 暴力破解字符集
    int        resume;              // 断点续传标志
    int        thread_count;        // 多线程数量（深空之眼）
    int        show_progress;       // 显示实时进度
} Config;

/* 目标哈希链表节点（存储待破解的哈希及结果） */
typedef struct HashNode {
    char hash[MAX_HASH_LEN];
    char plain[MAX_PASS_LEN];       // 破解出的明文，空串表示未破解
    struct HashNode *next;
} HashNode;

/* 暴力破解进度状态（用于断点续传） */
typedef struct {
    int current_len;        // 当前正在破解的密码长度
    int *indices;           // 当前密码在字符集中的索引数组（长度 = current_len）
    long long total_tried;  // 已尝试的密码总数（用于进度显示）
} BruteProgress;

/* ------------------------------- 全局变量 --------------------------------- */
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
    .thread_count = DEFAULT_THREAD_COUNT,
    .show_progress = 1
};

HashNode *g_hash_list = NULL;
int g_total_hashes = 0;
int g_cracked_count = 0;
pthread_mutex_t g_cracked_mutex = PTHREAD_MUTEX_INITIALIZER;
volatile sig_atomic_t g_should_exit = 0;   // 信号处理标志
BruteProgress g_brute_progress = {0, NULL, 0};
clock_t g_start_time = 0;

/* ------------------------------- 函数声明 --------------------------------- */
void signal_handler(int sig);
void parse_arguments(int argc, char *argv[]);
void load_hashes(const char *filename);
void save_results();
void compute_hash(const char *password, char *hash_out);
int  check_and_record(const char *password);
void dict_attack();
void reso_dict_attack();
void brute_attack_single();
void brute_attack_multi();
void brute_attack_resumable();
void run_cracker();
void print_usage(const char *prog);
void print_progress(long long tried, long long total_combinations);
long long count_combinations(int max_len, int charset_len);

/* ------------------------------- 哈希计算模块 ----------------------------- */
void compute_md5(const char *input, char *output) {
    unsigned char digest[MD5_DIGEST_LENGTH];
    MD5((unsigned char*)input, strlen(input), digest);
    for (int i = 0; i < MD5_DIGEST_LENGTH; i++)
        sprintf(output + i*2, "%02x", digest[i]);
    output[MD5_DIGEST_LENGTH*2] = '\0';
}

void compute_sha1(const char *input, char *output) {
    unsigned char digest[SHA_DIGEST_LENGTH];
    SHA1((unsigned char*)input, strlen(input), digest);
    for (int i = 0; i < SHA_DIGEST_LENGTH; i++)
        sprintf(output + i*2, "%02x", digest[i]);
    output[SHA_DIGEST_LENGTH*2] = '\0';
}

void compute_sha256(const char *input, char *output) {
    unsigned char digest[SHA256_DIGEST_LENGTH];
    SHA256((unsigned char*)input, strlen(input), digest);
    for (int i = 0; i < SHA256_DIGEST_LENGTH; i++)
        sprintf(output + i*2, "%02x", digest[i]);
    output[SHA256_DIGEST_LENGTH*2] = '\0';
}

void compute_hash(const char *password, char *hash_out) {
    switch (g_config.hash_type) {
        case HASH_MD5:    compute_md5(password, hash_out); break;
        case HASH_SHA1:   compute_sha1(password, hash_out); break;
        case HASH_SHA256: compute_sha256(password, hash_out); break;
        default:          compute_md5(password, hash_out);
    }
}

/* ------------------------------- 目标哈希管理 ----------------------------- */
void load_hashes(const char *filename) {
    FILE *fp = fopen(filename, "r");
    if (!fp) {
        perror("无法打开哈希文件");
        exit(EXIT_FAILURE);
    }
    char line[MAX_HASH_LEN];
    while (fgets(line, sizeof(line), fp)) {
        line[strcspn(line, "\n")] = '\0';
        if (strlen(line) == 0) continue;
        HashNode *node = (HashNode*)malloc(sizeof(HashNode));
        if (!node) { perror("内存分配失败"); exit(EXIT_FAILURE); }
        strcpy(node->hash, line);
        node->plain[0] = '\0';
        node->next = g_hash_list;
        g_hash_list = node;
        g_total_hashes++;
    }
    fclose(fp);
    printf("[*] 已加载 %d 个目标哈希\n", g_total_hashes);
}

/* 保存破解结果到文件（如果指定了输出文件） */
void save_results() {
    if (strlen(g_config.output_file) == 0) return;
    FILE *fp = fopen(g_config.output_file, "w");
    if (!fp) {
        fprintf(stderr, "警告：无法写入输出文件 %s\n", g_config.output_file);
        return;
    }
    for (HashNode *node = g_hash_list; node; node = node->next) {
        fprintf(fp, "%s:%s\n", node->hash, node->plain[0] ? node->plain : "?");
    }
    fclose(fp);
    printf("[*] 结果已保存至 %s\n", g_config.output_file);
}

/* 检查密码是否匹配任何未破解的哈希 */
int check_and_record(const char *password) {
    char hash[MAX_HASH_LEN];
    compute_hash(password, hash);
    int found = 0;
    pthread_mutex_lock(&g_cracked_mutex);
    for (HashNode *node = g_hash_list; node; node = node->next) {
        if (node->plain[0] == '\0' && strcmp(node->hash, hash) == 0) {
            strcpy(node->plain, password);
            g_cracked_count++;
            found = 1;
            printf("[+] 破解成功: \"%s\" -> %s\n", password, node->hash);
            fflush(stdout);
        }
    }
    pthread_mutex_unlock(&g_cracked_mutex);
    return found;
}

/* 打印最终结果摘要 */
void print_final_results() {
    printf("\n========== 破解结果 ==========\n");
    printf("总计哈希数: %d, 已破解: %d\n", g_total_hashes, g_cracked_count);
    if (g_cracked_count == g_total_hashes) {
        printf("🎉 恭喜！所有哈希已破解！\n");
    } else {
        printf("⚠️ 仍有 %d 个哈希未破解\n", g_total_hashes - g_cracked_count);
    }
    printf("详细结果:\n");
    for (HashNode *node = g_hash_list; node; node = node->next) {
        if (node->plain[0])
            printf("  %s : %s\n", node->hash, node->plain);
        else
            printf("  %s : [未破解]\n", node->hash);
    }
    double elapsed = (double)(clock() - g_start_time) / CLOCKS_PER_SEC;
    printf("耗时: %.2f 秒\n", elapsed);
}

/* ------------------------------- 进度显示辅助 ----------------------------- */
long long count_combinations(int max_len, int charset_len) {
    long long total = 0;
    long long power = 1;
    for (int len = 1; len <= max_len; len++) {
        power *= charset_len;
        total += power;
        if (total < 0) return -1;  // 溢出，不再精确计算
    }
    return total;
}

void print_progress(long long tried, long long total) {
    if (!g_config.show_progress) return;
    double elapsed = (double)(clock() - g_start_time) / CLOCKS_PER_SEC;
    double speed = tried / elapsed;
    double percent = (total > 0) ? (tried * 100.0 / total) : 0.0;
    printf("\r[进度] 已尝试: %lld (%.2f%%) | 速度: %.0f 密码/秒 | 已用: %.1fs",
           tried, percent, speed, elapsed);
    fflush(stdout);
}

/* ------------------------------- 字典攻击 --------------------------------- */
/* 普通字典攻击 */
void dict_attack() {
    printf("[*] 开始字典攻击，词典: %s\n", g_config.dict_file);
    FILE *fp = fopen(g_config.dict_file, "r");
    if (!fp) {
        perror("无法打开字典文件");
        return;
    }
    char line[MAX_PASS_LEN];
    long long tried = 0;
    while (fgets(line, sizeof(line), fp) && !g_should_exit) {
        line[strcspn(line, "\n")] = '\0';
        tried++;
        if (check_and_record(line))
            if (g_cracked_count == g_total_hashes) break;
        if (tried % 10000 == 0) print_progress(tried, tried); // 显示已尝试行数
    }
    fclose(fp);
    printf("\n[*] 字典攻击完成，共尝试 %lld 个密码\n", tried);
}

/* 雷索纳斯主题：频率共振模式，先尝试内置高频弱密码，再读字典 */
static const char *g_weak_passwords[] = {
    "123456", "password", "12345678", "qwerty", "12345", "123456789",
    "football", "1234", "1234567", "baseball", "welcome", "1234567890",
    "abc123", "111111", "1qaz2wsx", "admin", "letmein", "monkey",
    "master", "hello", "123123", "654321", "password123", NULL
};

void reso_dict_attack() {
    printf("[⚡ 雷索纳斯·频率共振] 优先按频率尝试弱密码...\n");
    for (int i = 0; g_weak_passwords[i] != NULL && !g_should_exit; i++) {
        if (check_and_record(g_weak_passwords[i]))
            if (g_cracked_count == g_total_hashes) return;
        usleep(1000); // 模拟共振延迟，避免CPU满载
    }
    printf("[⚡ 频率共振] 弱密码尝试完毕，开始常规字典攻击...\n");
    dict_attack();
}

/* ------------------------------- 暴力破解模块 ----------------------------- */
/* 单线程暴力破解（阴阳师主题） */
void brute_force_recursive(char *prefix, int len, int max_len, const char *charset, int charset_len,
                           long long *tried) {
    if (g_should_exit || g_cracked_count == g_total_hashes) return;
    if (len == max_len) {
        prefix[len] = '\0';
        check_and_record(prefix);
        (*tried)++;
        if (*tried % PROGRESS_UPDATE_INTERVAL == 0)
            print_progress(*tried, -1);
        return;
    }
    for (int i = 0; i < charset_len && !g_should_exit && g_cracked_count < g_total_hashes; i++) {
        prefix[len] = charset[i];
        brute_force_recursive(prefix, len+1, max_len, charset, charset_len, tried);
    }
}

void brute_attack_single() {
    printf("[*] 单线程暴力破解，最大长度 %d，字符集大小 %zu\n",
           g_config.brute_max_len, strlen(g_config.brute_charset));
    long long total_comb = count_combinations(g_config.brute_max_len, strlen(g_config.brute_charset));
    if (total_comb > 0) printf("[*] 预计总组合数: %lld\n", total_comb);
    long long tried = 0;
    char password[MAX_PASS_LEN+1];
    for (int len = 1; len <= g_config.brute_max_len && !g_should_exit && g_cracked_count < g_total_hashes; len++) {
        brute_force_recursive(password, 0, len, g_config.brute_charset, strlen(g_config.brute_charset), &tried);
    }
    print_progress(tried, total_comb);
    printf("\n[*] 暴力破解完成，共尝试 %lld 个密码\n", tried);
}

/* 深空之眼：多线程暴力破解（工作线程） */
typedef struct {
    int thread_id;
    int max_len;
    int charset_len;
    char charset[96];
    int start_idx;   // 首字符起始索引
    int step;        // 步长
    long long tried; // 本线程尝试次数
} MultiThreadData;

void *brute_worker(void *arg) {
    MultiThreadData *data = (MultiThreadData*)arg;
    int charset_len = data->charset_len;
    char *charset = data->charset;
    int max_len = data->max_len;
    int start = data->start_idx;
    int step = data->step;
    long long tried = 0;
    char prefix[MAX_PASS_LEN+1];
    
    // 辅助递归函数（生成后缀）
    void rec(int pos, int target_len, char *base, int base_len) {
        if (g_should_exit || g_cracked_count == g_total_hashes) return;
        if (pos == target_len) {
            base[base_len + pos] = '\0';
            check_and_record(base);
            tried++;
            if (tried % PROGRESS_UPDATE_INTERVAL == 0) {
                // 注意：多线程下进度显示可能乱序，此处简化，不加锁
            }
            return;
        }
        for (int c = 0; c < charset_len && !g_should_exit && g_cracked_count < g_total_hashes; c++) {
            base[base_len + pos] = charset[c];
            rec(pos+1, target_len, base, base_len);
        }
    }
    
    for (int len = 1; len <= max_len && !g_should_exit && g_cracked_count < g_total_hashes; len++) {
        if (len == 1) {
            for (int i = start; i < charset_len; i += step) {
                if (g_should_exit || g_cracked_count == g_total_hashes) break;
                prefix[0] = charset[i];
                prefix[1] = '\0';
                check_and_record(prefix);
                tried++;
            }
        } else {
            for (int first = start; first < charset_len; first += step) {
                if (g_should_exit || g_cracked_count == g_total_hashes) break;
                prefix[0] = charset[first];
                rec(0, len-1, prefix, 1);
            }
        }
    }
    data->tried = tried;
    return NULL;
}

void brute_attack_multi() {
    printf("[⚔️ 深空之眼·动作战斗] 多线程暴力破解，线程数 %d\n", g_config.thread_count);
    int charset_len = strlen(g_config.brute_charset);
    long long total_comb = count_combinations(g_config.brute_max_len, charset_len);
    if (total_comb > 0) printf("[*] 预计总组合数: %lld\n", total_comb);
    
    pthread_t threads[g_config.thread_count];
    MultiThreadData thread_data[g_config.thread_count];
    
    for (int i = 0; i < g_config.thread_count; i++) {
        thread_data[i].thread_id = i;
        thread_data[i].max_len = g_config.brute_max_len;
        thread_data[i].charset_len = charset_len;
        strcpy(thread_data[i].charset, g_config.brute_charset);
        thread_data[i].start_idx = i;
        thread_data[i].step = g_config.thread_count;
        thread_data[i].tried = 0;
        pthread_create(&threads[i], NULL, brute_worker, &thread_data[i]);
    }
    
    long long total_tried = 0;
    // 主线程定期显示总进度
    while (!g_should_exit && g_cracked_count < g_total_hashes) {
        sleep(1);
        total_tried = 0;
        for (int i = 0; i < g_config.thread_count; i++)
            total_tried += thread_data[i].tried;
        print_progress(total_tried, total_comb);
    }
    
    for (int i = 0; i < g_config.thread_count; i++) {
        pthread_join(threads[i], NULL);
        total_tried += thread_data[i].tried;
    }
    print_progress(total_tried, total_comb);
    printf("\n[*] 多线程暴力破解完成，共尝试 %lld 个密码\n", total_tried);
}

/* 重返未来·时间旅行：断点续传暴力破解（单线程，支持保存/恢复） */
void save_brute_progress(int len, int *indices, long long tried) {
    FILE *fp = fopen(PROGRESS_FILE, "wb");
    if (!fp) return;
    fwrite(&len, sizeof(int), 1, fp);
    fwrite(indices, sizeof(int), len, fp);
    fwrite(&tried, sizeof(long long), 1, fp);
    fclose(fp);
}

int load_brute_progress(int **indices, long long *tried) {
    FILE *fp = fopen(PROGRESS_FILE, "rb");
    if (!fp) return -1;
    int len;
    fread(&len, sizeof(int), 1, fp);
    *indices = (int*)malloc(len * sizeof(int));
    fread(*indices, sizeof(int), len, fp);
    fread(tried, sizeof(long long), 1, fp);
    fclose(fp);
    return len;
}

void brute_attack_resumable() {
    printf("[⏳ 重返未来·时间旅行] 断点续传暴力破解，最大长度 %d\n", g_config.brute_max_len);
    int charset_len = strlen(g_config.brute_charset);
    long long total_comb = count_combinations(g_config.brute_max_len, charset_len);
    if (total_comb > 0) printf("[*] 预计总组合数: %lld\n", total_comb);
    
    int start_len = 1;
    int *indices = NULL;
    long long tried = 0;
    if (g_config.resume) {
        int loaded_len = load_brute_progress(&indices, &tried);
        if (loaded_len != -1) {
            start_len = loaded_len;
            printf("[*] 恢复进度，当前长度 %d，已尝试 %lld 个密码\n", start_len, tried);
        } else {
            printf("[*] 未找到进度文件，从头开始\n");
        }
    }
    
    if (!indices) {
        indices = (int*)malloc(g_config.brute_max_len * sizeof(int));
        memset(indices, 0, g_config.brute_max_len * sizeof(int));
    }
    
    char password[MAX_PASS_LEN+1];
    for (int len = start_len; len <= g_config.brute_max_len && !g_should_exit && g_cracked_count < g_total_hashes; len++) {
        if (len > start_len) {
            memset(indices, 0, len * sizeof(int));
            tried = 0; // 新长度重置尝试计数（进度显示用）
        }
        // 枚举当前长度的所有组合
        while (1) {
            if (g_should_exit || g_cracked_count == g_total_hashes) break;
            // 构造密码
            for (int i = 0; i < len; i++)
                password[i] = g_config.brute_charset[indices[i]];
            password[len] = '\0';
            check_and_record(password);
            tried++;
            if (tried % PROGRESS_UPDATE_INTERVAL == 0) {
                print_progress(tried, total_comb);
                save_brute_progress(len, indices, tried);
            }
            // 索引递增（N进制）
            int pos = len - 1;
            while (pos >= 0) {
                indices[pos]++;
                if (indices[pos] < charset_len) break;
                indices[pos] = 0;
                pos--;
            }
            if (pos < 0) break;  // 当前长度枚举完毕
        }
        start_len = len + 1; // 继续下一长度
    }
    print_progress(tried, total_comb);
    printf("\n[*] 断点续传暴力破解完成，共尝试 %lld 个密码\n", tried);
    remove(PROGRESS_FILE);
    free(indices);
}

/* ------------------------------- 主题调度 ------------------------------- */
void run_cracker() {
    switch (g_config.attack_mode) {
        case ATTACK_DICT:
            if (g_config.theme == THEME_RESO_NANCE)
                reso_dict_attack();
            else
                dict_attack();
            break;
        case ATTACK_BRUTE:
            switch (g_config.theme) {
                case THEME_DEEP_SPACE:
                    brute_attack_multi();
                    break;
                case THEME_REVERSE_1999:
                    brute_attack_resumable();
                    break;
                default:
                    brute_attack_single();
            }
            break;
    }
}

/* ------------------------------- 信号处理 --------------------------------- */
void signal_handler(int sig) {
    if (sig == SIGINT || sig == SIGTERM) {
        printf("\n[!] 收到中断信号，正在保存进度并退出...\n");
        g_should_exit = 1;
        if (g_config.attack_mode == ATTACK_BRUTE && g_config.theme == THEME_REVERSE_1999) {
            // 保存当前暴力破解进度（由主循环负责保存）
        }
    }
}

/* ------------------------------- 命令行解析 ------------------------------- */
void print_usage(const char *prog) {
    printf("用法: %s -t <主题> -a <攻击模式> -m <哈希类型> [选项] -H <哈希文件>\n\n", prog);
    printf("必需参数:\n");
    printf("  -t <主题>      yin-yang-shi, deep-space, reverse-1999, reso-nance\n");
    printf("  -a <模式>      dict (字典), brute (暴力)\n");
    printf("  -m <类型>      md5, sha1, sha256\n");
    printf("  -H <文件>      包含目标哈希的文件（每行一个哈希）\n\n");
    printf("字典攻击选项:\n");
    printf("  -d <文件>      密码字典文件\n\n");
    printf("暴力攻击选项:\n");
    printf("  -l <长度>      最大密码长度 (默认4)\n");
    printf("  -c <字符集>    自定义字符集 (默认 a-z0-9)\n");
    printf("  --resume       启用断点续传 (仅 reverse-1999 主题有效)\n");
    printf("  --threads <N>  线程数 (默认4, deep-space 主题有效)\n\n");
    printf("其他选项:\n");
    printf("  -o <文件>      保存破解结果到文件\n");
    printf("  --no-progress  关闭进度显示\n");
    printf("  -h             显示此帮助\n");
    exit(EXIT_FAILURE);
}

void parse_arguments(int argc, char *argv[]) {
    for (int i = 1; i < argc; i++) {
        if (strcmp(argv[i], "-t") == 0 && i+1 < argc) {
            i++;
            if (strcmp(argv[i], "yin-yang-shi") == 0) g_config.theme = THEME_YIN_YANG_SHI;
            else if (strcmp(argv[i], "deep-space") == 0) g_config.theme = THEME_DEEP_SPACE;
            else if (strcmp(argv[i], "reverse-1999") == 0) g_config.theme = THEME_REVERSE_1999;
            else if (strcmp(argv[i], "reso-nance") == 0) g_config.theme = THEME_RESO_NANCE;
            else { fprintf(stderr, "未知主题: %s\n", argv[i]); print_usage(argv[0]); }
        }
        else if (strcmp(argv[i], "-a") == 0 && i+1 < argc) {
            i++;
            if (strcmp(argv[i], "dict") == 0) g_config.attack_mode = ATTACK_DICT;
            else if (strcmp(argv[i], "brute") == 0) g_config.attack_mode = ATTACK_BRUTE;
            else { fprintf(stderr, "未知攻击模式: %s\n", argv[i]); print_usage(argv[0]); }
        }
        else if (strcmp(argv[i], "-m") == 0 && i+1 < argc) {
            i++;
            if (strcmp(argv[i], "md5") == 0) g_config.hash_type = HASH_MD5;
            else if (strcmp(argv[i], "sha1") == 0) g_config.hash_type = HASH_SHA1;
            else if (strcmp(argv[i], "sha256") == 0) g_config.hash_type = HASH_SHA256;
            else { fprintf(stderr, "未知哈希类型: %s\n", argv[i]); print_usage(argv[0]); }
        }
        else if (strcmp(argv[i], "-d") == 0 && i+1 < argc) strcpy(g_config.dict_file, argv[++i]);
        else if (strcmp(argv[i], "-H") == 0 && i+1 < argc) strcpy(g_config.hash_file, argv[++i]);
        else if (strcmp(argv[i], "-o") == 0 && i+1 < argc) strcpy(g_config.output_file, argv[++i]);
        else if (strcmp(argv[i], "-l") == 0 && i+1 < argc) g_config.brute_max_len = atoi(argv[++i]);
        else if (strcmp(argv[i], "-c") == 0 && i+1 < argc) strcpy(g_config.brute_charset, argv[++i]);
        else if (strcmp(argv[i], "--resume") == 0) g_config.resume = 1;
        else if (strcmp(argv[i], "--threads") == 0 && i+1 < argc) g_config.thread_count = atoi(argv[++i]);
        else if (strcmp(argv[i], "--no-progress") == 0) g_config.show_progress = 0;
        else if (strcmp(argv[i], "-h") == 0) print_usage(argv[0]);
        else { fprintf(stderr, "未知选项: %s\n", argv[i]); print_usage(argv[0]); }
    }
    if (strlen(g_config.hash_file) == 0) {
        fprintf(stderr, "错误：必须指定哈希文件 (-H)\n");
        print_usage(argv[0]);
    }
    if (g_config.attack_mode == ATTACK_DICT && strlen(g_config.dict_file) == 0) {
        fprintf(stderr, "错误：字典模式需要字典文件 (-d)\n");
        print_usage(argv[0]);
    }
    if (g_config.theme == THEME_DEEP_SPACE && g_config.thread_count <= 0)
        g_config.thread_count = DEFAULT_THREAD_COUNT;
    if (strlen(g_config.brute_charset) == 0) strcpy(g_config.brute_charset, "abcdefghijklmnopqrstuvwxyz0123456789");
}

/* ------------------------------- 主函数 --------------------------------- */
int main(int argc, char *argv[]) {
    signal(SIGINT, signal_handler);
    signal(SIGTERM, signal_handler);
    parse_arguments(argc, argv);
    load_hashes(g_config.hash_file);
    
    printf("========================================\n");
    printf("  主题哈希破解工具\n");
    printf("  主题: %s | 攻击: %s | 哈希: %s\n",
           (g_config.theme == THEME_YIN_YANG_SHI) ? "阴阳师" :
           (g_config.theme == THEME_DEEP_SPACE) ? "深空之眼" :
           (g_config.theme == THEME_REVERSE_1999) ? "重返未来1999" : "雷索纳斯",
           (g_config.attack_mode == ATTACK_DICT) ? "字典" : "暴力",
           (g_config.hash_type == HASH_MD5) ? "MD5" :
           (g_config.hash_type == HASH_SHA1) ? "SHA1" : "SHA256");
    printf("========================================\n");
    
    g_start_time = clock();
    run_cracker();
    print_final_results();
    save_results();
    
    // 释放哈希链表内存
    HashNode *node = g_hash_list;
    while (node) {
        HashNode *next = node->next;
        free(node);
        node = next;
    }
    return 0;
}