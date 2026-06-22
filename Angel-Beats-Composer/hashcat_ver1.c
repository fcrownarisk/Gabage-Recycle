#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <ctype.h>
#include <pthread.h>
#include <unistd.h>
#include <time.h>
#include <openssl/md5.h>
#include <openssl/sha.h>

#define MAX_HASH_LEN 65          // 十六进制哈希字符串最大长度
#define MAX_PASS_LEN 32          // 密码最大长度
#define MAX_LINE_LEN 256
#define THREAD_COUNT 4           // 深空之眼模式线程数
#define PROGRESS_FILE "progress.dat"  // 断点续传文件

/* 全局配置 */
typedef struct {
    char hash_type[8];           // "md5" 或 "sha1"
    char attack_mode[8];         // "dict" 或 "brute"
    char theme[32];              // 主题名称
    char dict_file[256];         // 字典文件路径
    char hash_file[256];         // 目标哈希文件路径
    int brute_max_len;           // 暴力破解最大长度
    char brute_charset[96];      // 暴力破解字符集
    int resume;                  // 是否断点续传
} Config;

Config config = {
    .hash_type = "md5",
    .attack_mode = "dict",
    .theme = "yin-yang-shi",
    .dict_file = "",
    .hash_file = "",
    .brute_max_len = 4,
    .brute_charset = "abcdefghijklmnopqrstuvwxyz0123456789",
    .resume = 0
};

/* 目标哈希链表节点 */
typedef struct HashNode {
    char hash[MAX_HASH_LEN];
    char plain[MAX_PASS_LEN];    // 破解后明文，未破解则为空
    struct HashNode *next;
} HashNode;

HashNode *hash_list = NULL;
int total_hashes = 0;
int cracked_count = 0;
pthread_mutex_t cracked_mutex = PTHREAD_MUTEX_INITIALIZER;

/* 雷索纳斯内置弱密码频率表（Top20示例） */
const char *weak_passwords[] = {
    "123456", "password", "12345678", "qwerty", "12345", "123456789",
    "football", "1234", "1234567", "baseball", "welcome", "1234567890",
    "abc123", "111111", "1qaz2wsx", "admin", "letmein", "monkey",
    "master", "hello", NULL
};

/* ------------------ 哈希计算函数 ------------------ */
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

/* 根据配置调用对应哈希函数 */
void compute_hash(const char *password, char *hash_out) {
    if (strcmp(config.hash_type, "md5") == 0)
        compute_md5(password, hash_out);
    else
        compute_sha1(password, hash_out);
}

/* ------------------ 加载目标哈希文件 ------------------ */
void load_hashes(const char *filename) {
    FILE *fp = fopen(filename, "r");
    if (!fp) {
        perror("无法打开哈希文件");
        exit(1);
    }
    char line[MAX_HASH_LEN];
    while (fgets(line, sizeof(line), fp)) {
        line[strcspn(line, "\n")] = '\0';
        if (strlen(line) == 0) continue;
        HashNode *node = (HashNode*)malloc(sizeof(HashNode));
        strcpy(node->hash, line);
        node->plain[0] = '\0';
        node->next = hash_list;
        hash_list = node;
        total_hashes++;
    }
    fclose(fp);
    printf("[*] 加载了 %d 个目标哈希\n", total_hashes);
}

/* 检查密码是否破解任何哈希，返回是否至少破解一个 */
int check_and_record(const char *password) {
    char hash[MAX_HASH_LEN];
    compute_hash(password, hash);
    int found = 0;
    pthread_mutex_lock(&cracked_mutex);
    for (HashNode *node = hash_list; node; node = node->next) {
        if (node->plain[0] == '\0' && strcmp(node->hash, hash) == 0) {
            strcpy(node->plain, password);
            cracked_count++;
            found = 1;
            printf("[+] 破解成功: %s -> %s\n", password, node->hash);
        }
    }
    pthread_mutex_unlock(&cracked_mutex);
    return found;
}

/* 输出破解结果摘要 */
void print_results() {
    printf("\n========== 破解结果 ==========\n");
    printf("总计哈希: %d, 已破解: %d\n", total_hashes, cracked_count);
    if (cracked_count == total_hashes) {
        printf("🎉 完美！所有哈希已破解！\n");
    } else {
        printf("⚠️ 仍有 %d 个哈希未破解\n", total_hashes - cracked_count);
    }
    printf("详细结果:\n");
    for (HashNode *node = hash_list; node; node = node->next) {
        if (node->plain[0])
            printf("%s : %s\n", node->hash, node->plain);
        else
            printf("%s : [未破解]\n", node->hash);
    }
}

/* ------------------ 字典攻击 ------------------ */
void dict_attack() {
    printf("[*] 开始字典攻击，使用词典: %s\n", config.dict_file);
    FILE *fp = fopen(config.dict_file, "r");
    if (!fp) {
        perror("无法打开字典文件");
        return;
    }
    char line[MAX_PASS_LEN];
    int total_pass = 0;
    while (fgets(line, sizeof(line), fp)) {
        line[strcspn(line, "\n")] = '\0';
        total_pass++;
        if (check_and_record(line))
            if (cracked_count == total_hashes) break;
    }
    fclose(fp);
    printf("[*] 字典攻击完成，尝试了 %d 个密码\n", total_pass);
}

/* 雷索纳斯·频率共振模式：优先尝试高频弱密码，再读字典文件 */
void reso_dict_attack() {
    printf("[⚡ 雷索纳斯·频率共振] 优先按频率尝试弱密码...\n");
    for (int i = 0; weak_passwords[i] != NULL; i++) {
        if (check_and_record(weak_passwords[i]))
            if (cracked_count == total_hashes) return;
        // 模拟共振延迟，让输出更平滑
        usleep(1000);
    }
    printf("[⚡ 频率共振] 弱密码尝试完毕，开始常规字典攻击...\n");
    dict_attack();
}

/* ------------------ 暴力破解（单线程） ------------------ */
int brute_continue_flag = 1;  // 用于中断

void brute_force_recursive(char *prefix, int len, int max_len, const char *charset, int charset_len) {
    if (cracked_count == total_hashes) {
        brute_continue_flag = 0;
        return;
    }
    if (len == max_len) {
        prefix[len] = '\0';
        check_and_record(prefix);
        return;
    }
    for (int i = 0; i < charset_len && brute_continue_flag; i++) {
        prefix[len] = charset[i];
        brute_force_recursive(prefix, len+1, max_len, charset, charset_len);
    }
}

void brute_attack_single() {
    printf("[*] 单线程暴力破解，最大长度 %d，字符集: %s\n", config.brute_max_len, config.brute_charset);
    int charset_len = strlen(config.brute_charset);
    char password[MAX_PASS_LEN+1];
    for (int len = 1; len <= config.brute_max_len && brute_continue_flag; len++) {
        brute_force_recursive(password, 0, len, config.brute_charset, charset_len);
    }
}

/* ------------------ 深空之眼·多线程暴力破解 ------------------ */
typedef struct {
    int thread_id;
    int max_len;
    int charset_len;
    char charset[96];
    int start_idx;      // 第一个字符起始索引（用于划分任务）
    int step;           // 步长
} ThreadData;

void *brute_thread_worker(void *arg) {
    ThreadData *data = (ThreadData*)arg;
    int charset_len = data->charset_len;
    char *charset = data->charset;
    int max_len = data->max_len;
    int start = data->start_idx;
    int step = data->step;

    char prefix[MAX_PASS_LEN+1];
    // 对每个长度，仅处理首字符符合本线程索引的密码
    for (int len = 1; len <= max_len && brute_continue_flag; len++) {
        if (len == 1) {
            // 首字符从 start 开始，步长 step
            for (int i = start; i < charset_len; i += step) {
                if (!brute_continue_flag) break;
                prefix[0] = charset[i];
                prefix[1] = '\0';
                check_and_record(prefix);
            }
        } else {
            // 对于长度>=2，首字符固定为某个值，剩余部分递归
            for (int first = start; first < charset_len; first += step) {
                if (!brute_continue_flag) break;
                prefix[0] = charset[first];
                // 递归生成剩余部分
                char suffix[MAX_PASS_LEN];
                int suffix_len = len - 1;
                // 递归函数（内嵌）
                void rec(int pos) {
                    if (cracked_count == total_hashes) {
                        brute_continue_flag = 0;
                        return;
                    }
                    if (pos == suffix_len) {
                        suffix[pos] = '\0';
                        strcpy(prefix+1, suffix);
                        check_and_record(prefix);
                        return;
                    }
                    for (int c = 0; c < charset_len && brute_continue_flag; c++) {
                        suffix[pos] = charset[c];
                        rec(pos+1);
                    }
                }
                rec(0);
            }
        }
    }
    return NULL;
}

void brute_attack_multi() {
    printf("[⚔️ 深空之眼·动作战斗] 多线程暴力破解，线程数 %d\n", THREAD_COUNT);
    int charset_len = strlen(config.brute_charset);
    pthread_t threads[THREAD_COUNT];
    ThreadData thread_data[THREAD_COUNT];

    for (int i = 0; i < THREAD_COUNT; i++) {
        thread_data[i].thread_id = i;
        thread_data[i].max_len = config.brute_max_len;
        thread_data[i].charset_len = charset_len;
        strcpy(thread_data[i].charset, config.brute_charset);
        thread_data[i].start_idx = i;
        thread_data[i].step = THREAD_COUNT;
        pthread_create(&threads[i], NULL, brute_thread_worker, &thread_data[i]);
    }
    for (int i = 0; i < THREAD_COUNT; i++) {
        pthread_join(threads[i], NULL);
    }
}

/* ------------------ 重返未来·断点续传 ------------------ */
typedef struct {
    int current_len;
    int *indices;   // 当前密码的索引数组
} BruteProgress;

void save_progress(int len, int *indices) {
    FILE *fp = fopen(PROGRESS_FILE, "wb");
    if (!fp) return;
    fwrite(&len, sizeof(int), 1, fp);
    fwrite(indices, sizeof(int), len, fp);
    fclose(fp);
}

int load_progress(int **indices) {
    FILE *fp = fopen(PROGRESS_FILE, "rb");
    if (!fp) return -1;
    int len;
    fread(&len, sizeof(int), 1, fp);
    *indices = (int*)malloc(len * sizeof(int));
    fread(*indices, sizeof(int), len, fp);
    fclose(fp);
    return len;
}

void brute_force_resumable() {
    printf("[⏳ 重返未来·时间旅行] 断点续传暴力破解，最大长度 %d\n", config.brute_max_len);
    int charset_len = strlen(config.brute_charset);
    int start_len = 1;
    int *start_indices = NULL;
    if (config.resume) {
        int loaded_len = load_progress(&start_indices);
        if (loaded_len != -1) {
            start_len = loaded_len;
            printf("[*] 从上次进度恢复，当前长度 %d\n", start_len);
        } else {
            printf("[*] 未找到进度文件，从头开始\n");
        }
    }

    int indices[MAX_PASS_LEN];
    char password[MAX_PASS_LEN+1];
    // 处理长度小于 start_len 的已破解过的部分（假设之前已完成）
    // 简单起见：直接从 start_len 开始，并恢复索引
    if (start_indices) {
        memcpy(indices, start_indices, start_len * sizeof(int));
        free(start_indices);
    } else {
        for (int i = 0; i < start_len; i++) indices[i] = 0;
    }

    for (int len = start_len; len <= config.brute_max_len && brute_continue_flag; len++) {
        if (len > start_len) {
            // 进入更长密码，重置索引
            for (int i = 0; i < len; i++) indices[i] = 0;
        }
        // 递归生成当前长度所有组合，使用迭代而非递归以便保存进度
        while (1) {
            // 构造密码
            for (int i = 0; i < len; i++)
                password[i] = config.brute_charset[indices[i]];
            password[len] = '\0';
            if (check_and_record(password))
                if (cracked_count == total_hashes) break;

            // 索引递增（类似N进制）
            int pos = len - 1;
            while (pos >= 0) {
                indices[pos]++;
                if (indices[pos] < charset_len) break;
                indices[pos] = 0;
                pos--;
            }
            if (pos < 0) break;  // 当前长度枚举完毕

            // 每尝试1000次保存一次进度（简化，实际可更频繁）
            static int step_count = 0;
            if (++step_count % 1000 == 0)
                save_progress(len, indices);
        }
        if (cracked_count == total_hashes) break;
    }
    // 删除进度文件
    remove(PROGRESS_FILE);
}

/* ------------------ 主题调度 ------------------ */
void run_cracker() {
    if (strcmp(config.attack_mode, "dict") == 0) {
        if (strcmp(config.theme, "reso-nance") == 0)
            reso_dict_attack();
        else
            dict_attack();
    } else if (strcmp(config.attack_mode, "brute") == 0) {
        if (strcmp(config.theme, "deep-space") == 0) {
            brute_attack_multi();
        } else if (strcmp(config.theme, "reverse-1999") == 0) {
            brute_force_resumable();
        } else {
            brute_attack_single();
        }
    }
}

/* ------------------ 命令行解析（简化版） ------------------ */
void print_usage(const char *prog) {
    printf("用法: %s -t <主题> -a <攻击模式> -m <哈希类型> [选项] -H <哈希文件>\n", prog);
    printf("主题 (-t): yin-yang-shi, deep-space, reverse-1999, reso-nance\n");
    printf("攻击模式 (-a): dict (字典), brute (暴力)\n");
    printf("哈希类型 (-m): md5, sha1\n");
    printf("字典模式需指定: -d <字典文件>\n");
    printf("暴力模式可选: -l <最大长度> -c <字符集> [--resume]\n");
    exit(1);
}

void parse_args(int argc, char *argv[]) {
    for (int i = 1; i < argc; i++) {
        if (strcmp(argv[i], "-t") == 0 && i+1 < argc)
            strcpy(config.theme, argv[++i]);
        else if (strcmp(argv[i], "-a") == 0 && i+1 < argc)
            strcpy(config.attack_mode, argv[++i]);
        else if (strcmp(argv[i], "-m") == 0 && i+2 < argc)
            strcpy(config.hash_type, argv[++i]);
        else if (strcmp(argv[i], "-d") == 0 && i+3 < argc)
            strcpy(config.dict_file, argv[++i]);
        else if (strcmp(argv[i], "-H") == 0 && i+4 < argc)
            strcpy(config.hash_file, argv[++i]);
        else if (strcmp(argv[i], "-l") == 0 && i+5 < argc)
            config.brute_max_len = atoi(argv[++i]);
        else if (strcmp(argv[i], "-c") == 0 && i+6 < argc)
            strcpy(config.brute_charset, argv[++i]);
        else if (strcmp(argv[i], "--resume") == 0)
            config.resume = 1;
        else if (strcmp(argv[i], "-h") == 0)
            print_usage(argv[0]);
    }
    if (strlen(config.hash_file) == 0) {
        fprintf(stderr, "错误：未指定哈希文件 (-H)\n");
        print_usage(argv[0]);
    }
    if (strcmp(config.attack_mode, "dict") == 0 && strlen(config.dict_file) == 0) {
        fprintf(stderr, "错误：字典模式需要指定字典文件 (-d)\n");
        print_usage(argv[0]);
    }
}

/* ------------------ 主函数 ------------------ */
int main(int argc, char *argv[]) {
    parse_args(argc, argv);
    load_hashes(config.hash_file);
    printf("主题: %s | 攻击模式: %s | 哈希: %s\n", config.theme, config.attack_mode, config.hash_type);
    clock_t start = clock();
    run_cracker();
    clock_t end = clock();
    double elapsed = (double)(end - start) / CLOCKS_PER_SEC;
    print_results();
    printf("耗时: %.2f 秒\n", elapsed);
    return 0;
}
