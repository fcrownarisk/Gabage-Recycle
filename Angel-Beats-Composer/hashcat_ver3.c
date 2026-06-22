/**
 * simple_hashcat.c - 简化版HashCat实现
 * 支持字典攻击、掩码攻击、基本规则、多线程
 * 编译: gcc -o simple_hashcat simple_hashcat.c -lcrypto -lpthread -O2 -Wall
 */

#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <ctype.h>
#include <pthread.h>
#include <unistd.h>
#include <time.h>
#include <openssl/md5.h>
#include <openssl/sha.h>

/* ------------------------------- 常量定义 --------------------------------- */
#define MAX_HASH_LEN     128
#define MAX_PASS_LEN     64
#define MAX_LINE_LEN     256
#define MAX_RULE_LEN     256
#define MAX_RULES        10000
#define DEFAULT_THREADS  4

/* 哈希类型 */
typedef enum {
    HASH_MD5,
    HASH_SHA1,
    HASH_SHA256
} HashType;

/* 攻击模式 */
typedef enum {
    ATTACK_DICT,
    ATTACK_MASK
} AttackMode;

/* 全局配置 */
typedef struct {
    HashType   hash_type;
    AttackMode attack_mode;
    char       dict_file[256];
    char       hash_file[256];
    char       output_file[256];
    char       mask[256];          // 掩码字符串，如 "?l?l?l?d?d"
    char       rule_file[256];     // 规则文件路径（可选）
    int        threads;
    int        verbose;
} Config;

/* 哈希链表节点 */
typedef struct HashNode {
    char hash[MAX_HASH_LEN];
    char plain[MAX_PASS_LEN];
    struct HashNode *next;
} HashNode;

/* 规则结构（简单实现） */
typedef struct {
    char type;          // 'c': 首字母大写, 'u': 全大写, 'l': 全小写, 'r': 反转, '^': 前缀, '$': 后缀
    char arg[MAX_PASS_LEN];
} Rule;

/* ------------------------------- 全局变量 --------------------------------- */
Config g_config = {
    .hash_type = HASH_MD5,
    .attack_mode = ATTACK_DICT,
    .dict_file = "",
    .hash_file = "",
    .output_file = "",
    .mask = "",
    .rule_file = "",
    .threads = DEFAULT_THREADS,
    .verbose = 1
};

HashNode *g_hash_list = NULL;
int g_total_hashes = 0;
int g_cracked_count = 0;
pthread_mutex_t g_cracked_mutex = PTHREAD_MUTEX_INITIALIZER;
volatile int g_should_exit = 0;

Rule g_rules[MAX_RULES];
int g_rule_count = 0;

/* ------------------------------- 哈希计算 ------------------------------- */
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

/* ------------------------------- 哈希管理 ------------------------------- */
void load_hashes(const char *filename) {
    FILE *fp = fopen(filename, "r");
    if (!fp) {
        fprintf(stderr, "错误: 无法打开哈希文件 %s\n", filename);
        exit(1);
    }
    char line[MAX_HASH_LEN];
    while (fgets(line, sizeof(line), fp)) {
        line[strcspn(line, "\n")] = '\0';
        if (strlen(line) == 0) continue;
        HashNode *node = (HashNode*)malloc(sizeof(HashNode));
        strcpy(node->hash, line);
        node->plain[0] = '\0';
        node->next = g_hash_list;
        g_hash_list = node;
        g_total_hashes++;
    }
    fclose(fp);
    if (g_config.verbose)
        printf("[+] 加载了 %d 个目标哈希\n", g_total_hashes);
}

void save_results() {
    if (strlen(g_config.output_file) == 0) return;
    FILE *fp = fopen(g_config.output_file, "w");
    if (!fp) {
        fprintf(stderr, "警告: 无法写入输出文件 %s\n", g_config.output_file);
        return;
    }
    for (HashNode *node = g_hash_list; node; node = node->next) {
        if (node->plain[0])
            fprintf(fp, "%s:%s\n", node->hash, node->plain);
        else
            fprintf(fp, "%s:?\n", node->hash);
    }
    fclose(fp);
    if (g_config.verbose)
        printf("[+] 结果已保存到 %s\n", g_config.output_file);
}

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
            if (g_config.verbose)
                printf("[+] 破解成功: \"%s\" -> %s\n", password, node->hash);
        }
    }
    pthread_mutex_unlock(&g_cracked_mutex);
    return found;
}

/* ------------------------------- 规则引擎 ------------------------------- */
// 解析规则文件，每行一个规则
void load_rules(const char *filename) {
    FILE *fp = fopen(filename, "r");
    if (!fp) {
        if (g_config.verbose) printf("[-] 未找到规则文件，跳过规则\n");
        return;
    }
    char line[MAX_RULE_LEN];
    while (fgets(line, sizeof(line), fp) && g_rule_count < MAX_RULES) {
        line[strcspn(line, "\n")] = '\0';
        if (strlen(line) == 0 || line[0] == '#') continue;
        Rule r = {0};
        char *p = line;
        while (*p) {
            switch (*p) {
                case 'c': r.type = 'c'; p++; break;   // 首字母大写
                case 'u': r.type = 'u'; p++; break;   // 全大写
                case 'l': r.type = 'l'; p++; break;   // 全小写
                case 'r': r.type = 'r'; p++; break;   // 反转
                case '^': r.type = '^'; strcpy(r.arg, p+1); p += strlen(r.arg)+1; break; // 前缀
                case '$': r.type = '$'; strcpy(r.arg, p+1); p += strlen(r.arg)+1; break; // 后缀
                default: p++; break;
            }
        }
        if (r.type != 0) g_rules[g_rule_count++] = r;
    }
    fclose(fp);
    if (g_config.verbose) printf("[+] 加载了 %d 条规则\n", g_rule_count);
}

// 应用规则到原始单词，返回变形后的字符串（需自行分配缓冲区）
void apply_rule(const Rule *rule, const char *input, char *output) {
    strcpy(output, input);
    switch (rule->type) {
        case 'c': // 首字母大写
            if (output[0] >= 'a' && output[0] <= 'z')
                output[0] = toupper(output[0]);
            break;
        case 'u': // 全大写
            for (int i = 0; output[i]; i++)
                output[i] = toupper(output[i]);
            break;
        case 'l': // 全小写
            for (int i = 0; output[i]; i++)
                output[i] = tolower(output[i]);
            break;
        case 'r': // 反转
            {
                int len = strlen(output);
                for (int i = 0; i < len/2; i++) {
                    char tmp = output[i];
                    output[i] = output[len-1-i];
                    output[len-1-i] = tmp;
                }
            }
            break;
        case '^': // 前缀
            {
                char tmp[MAX_PASS_LEN];
                strcpy(tmp, output);
                sprintf(output, "%s%s", rule->arg, tmp);
            }
            break;
        case '$': // 后缀
            strcat(output, rule->arg);
            break;
    }
}

/* ------------------------------- 字典攻击（多线程） ------------------------- */
typedef struct {
    int thread_id;
    const char *dict_file;
    long start_line;
    long end_line;
    long *processed;
} DictThreadData;

// 获取文件总行数（简单实现）
long count_lines(const char *filename) {
    FILE *fp = fopen(filename, "r");
    if (!fp) return 0;
    long lines = 0;
    int ch;
    while ((ch = fgetc(fp)) != EOF)
        if (ch == '\n') lines++;
    fclose(fp);
    return lines;
}

void *dict_thread_worker(void *arg) {
    DictThreadData *data = (DictThreadData*)arg;
    FILE *fp = fopen(data->dict_file, "r");
    if (!fp) return NULL;
    
    // 跳到起始行
    long line_num = 0;
    char line[MAX_PASS_LEN];
    while (line_num < data->start_line && fgets(line, sizeof(line), fp))
        line_num++;
    
    char password[MAX_PASS_LEN];
    char modified[MAX_PASS_LEN];
    while (line_num < data->end_line && fgets(line, sizeof(line), fp) && !g_should_exit) {
        line[strcspn(line, "\n")] = '\0';
        line_num++;
        (*data->processed)++;
        
        // 原始密码尝试
        if (check_and_record(line))
            if (g_cracked_count == g_total_hashes) break;
        
        // 应用所有规则
        for (int i = 0; i < g_rule_count && !g_should_exit; i++) {
            apply_rule(&g_rules[i], line, modified);
            if (check_and_record(modified))
                if (g_cracked_count == g_total_hashes) break;
        }
    }
    fclose(fp);
    return NULL;
}

void dict_attack() {
    if (strlen(g_config.dict_file) == 0) {
        fprintf(stderr, "错误: 字典攻击需要指定字典文件 (-d)\n");
        return;
    }
    long total_lines = count_lines(g_config.dict_file);
    if (total_lines == 0) {
        fprintf(stderr, "错误: 字典文件为空或无法读取\n");
        return;
    }
    if (g_config.verbose)
        printf("[*] 字典攻击开始，字典行数: %ld，线程数: %d\n", total_lines, g_config.threads);
    
    pthread_t threads[g_config.threads];
    DictThreadData thread_data[g_config.threads];
    long lines_per_thread = total_lines / g_config.threads;
    long processed_array[g_config.threads];
    long total_processed = 0;
    
    for (int i = 0; i < g_config.threads; i++) {
        thread_data[i].thread_id = i;
        thread_data[i].dict_file = g_config.dict_file;
        thread_data[i].start_line = i * lines_per_thread;
        thread_data[i].end_line = (i == g_config.threads-1) ? total_lines : (i+1)*lines_per_thread;
        processed_array[i] = 0;
        thread_data[i].processed = &processed_array[i];
        pthread_create(&threads[i], NULL, dict_thread_worker, &thread_data[i]);
    }
    
    // 等待所有线程完成
    for (int i = 0; i < g_config.threads; i++) {
        pthread_join(threads[i], NULL);
        total_processed += processed_array[i];
    }
    if (g_config.verbose)
        printf("[*] 字典攻击完成，共处理 %ld 个单词（含规则变形）\n", total_processed);
}

/* ------------------------------- 掩码攻击（暴力） ------------------------- */
// 将掩码字符串转换为字符集数组和长度
typedef struct {
    char charset[96];
    int len;
} MaskSegment;

MaskSegment parse_mask_char(char c) {
    MaskSegment seg;
    switch (c) {
        case '?': seg.len = 0; break;  // 占位符，需要下一个字符
        case 'l': strcpy(seg.charset, "abcdefghijklmnopqrstuvwxyz"); seg.len = 26; break;
        case 'u': strcpy(seg.charset, "ABCDEFGHIJKLMNOPQRSTUVWXYZ"); seg.len = 26; break;
        case 'd': strcpy(seg.charset, "0123456789"); seg.len = 10; break;
        case 's': strcpy(seg.charset, "!\"#$%&'()*+,-./:;<=>?@[\\]^_`{|}~"); seg.len = 32; break;
        case 'a': strcpy(seg.charset, "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789!\"#$%&'()*+,-./:;<=>?@[\\]^_`{|}~"); seg.len = 94; break;
        default:  seg.charset[0] = c; seg.charset[1] = '\0'; seg.len = 1; break;
    }
    return seg;
}

void mask_attack_recursive(char *prefix, int pos, int max_len, MaskSegment *segments, long long *tried) {
    if (g_should_exit || g_cracked_count == g_total_hashes) return;
    if (pos == max_len) {
        prefix[pos] = '\0';
        check_and_record(prefix);
        (*tried)++;
        if (g_config.verbose && *tried % 100000 == 0) {
            printf("\r[进度] 已尝试 %lld 个密码", *tried);
            fflush(stdout);
        }
        return;
    }
    MaskSegment seg = segments[pos];
    for (int i = 0; i < seg.len && !g_should_exit && g_cracked_count < g_total_hashes; i++) {
        prefix[pos] = seg.charset[i];
        mask_attack_recursive(prefix, pos+1, max_len, segments, tried);
    }
}

void mask_attack() {
    if (strlen(g_config.mask) == 0) {
        fprintf(stderr, "错误: 掩码攻击需要指定掩码 (-k)\n");
        return;
    }
    // 解析掩码字符串，例如 "?l?l?l?d?d"
    int mask_len = 0;
    MaskSegment segments[MAX_PASS_LEN];
    for (int i = 0; g_config.mask[i] && mask_len < MAX_PASS_LEN; i++) {
        if (g_config.mask[i] == '?' && g_config.mask[i+1]) {
            i++;
            segments[mask_len++] = parse_mask_char(g_config.mask[i]);
        } else {
            segments[mask_len++] = parse_mask_char(g_config.mask[i]);
        }
    }
    if (mask_len == 0) {
        fprintf(stderr, "错误: 无效的掩码\n");
        return;
    }
    // 估算总组合数
    long long total = 1;
    for (int i = 0; i < mask_len; i++)
        total *= segments[i].len;
    if (g_config.verbose)
        printf("[*] 掩码攻击开始，长度 %d，总组合数约 %lld\n", mask_len, total);
    
    long long tried = 0;
    char password[MAX_PASS_LEN+1];
    mask_attack_recursive(password, 0, mask_len, segments, &tried);
    if (g_config.verbose)
        printf("\n[*] 掩码攻击完成，共尝试 %lld 个密码\n", tried);
}

/* ------------------------------- 主调度 ------------------------------- */
void run_cracker() {
    if (g_config.attack_mode == ATTACK_DICT)
        dict_attack();
    else if (g_config.attack_mode == ATTACK_MASK)
        mask_attack();
}

/* ------------------------------- 命令行解析 ------------------------------- */
void print_usage(const char *prog) {
    printf("用法: %s [选项]\n", prog);
    printf("必需选项:\n");
    printf("  -m <类型>    哈希类型: 0=MD5, 100=SHA1, 1400=SHA256\n");
    printf("  -a <模式>    攻击模式: 0=字典, 3=掩码\n");
    printf("  -H <文件>    目标哈希文件（每行一个哈希）\n");
    printf("字典模式选项:\n");
    printf("  -d <文件>    字典文件\n");
    printf("  -r <文件>    规则文件（可选）\n");
    printf("掩码模式选项:\n");
    printf("  -k <掩码>    掩码字符串，如 \"?l?l?l?d?d\"\n");
    printf("其他选项:\n");
    printf("  -o <文件>    输出破解结果到文件\n");
    printf("  -t <线程数>  线程数（默认4）\n");
    printf("  -q           安静模式（关闭详细输出）\n");
    printf("  -h           显示此帮助\n");
    exit(1);
}

void parse_args(int argc, char *argv[]) {
    for (int i = 1; i < argc; i++) {
        if (strcmp(argv[i], "-m") == 0 && i+1 < argc) {
            i++;
            int m = atoi(argv[i]);
            if (m == 0) g_config.hash_type = HASH_MD5;
            else if (m == 100) g_config.hash_type = HASH_SHA1;
            else if (m == 1400) g_config.hash_type = HASH_SHA256;
            else { fprintf(stderr, "不支持的哈希类型 %d\n", m); exit(1); }
        }
        else if (strcmp(argv[i], "-a") == 0 && i+1 < argc) {
            i++;
            int a = atoi(argv[i]);
            if (a == 0) g_config.attack_mode = ATTACK_DICT;
            else if (a == 3) g_config.attack_mode = ATTACK_MASK;
            else { fprintf(stderr, "不支持的攻击模式 %d\n", a); exit(1); }
        }
        else if (strcmp(argv[i], "-H") == 0 && i+1 < argc) strcpy(g_config.hash_file, argv[++i]);
        else if (strcmp(argv[i], "-d") == 0 && i+1 < argc) strcpy(g_config.dict_file, argv[++i]);
        else if (strcmp(argv[i], "-r") == 0 && i+1 < argc) strcpy(g_config.rule_file, argv[++i]);
        else if (strcmp(argv[i], "-k") == 0 && i+1 < argc) strcpy(g_config.mask, argv[++i]);
        else if (strcmp(argv[i], "-o") == 0 && i+1 < argc) strcpy(g_config.output_file, argv[++i]);
        else if (strcmp(argv[i], "-t") == 0 && i+1 < argc) g_config.threads = atoi(argv[++i]);
        else if (strcmp(argv[i], "-q") == 0) g_config.verbose = 0;
        else if (strcmp(argv[i], "-h") == 0) print_usage(argv[0]);
        else { fprintf(stderr, "未知选项: %s\n", argv[i]); print_usage(argv[0]); }
    }
    if (strlen(g_config.hash_file) == 0) {
        fprintf(stderr, "错误: 必须指定哈希文件 (-H)\n");
        print_usage(argv[0]);
    }
    if (g_config.attack_mode == ATTACK_DICT && strlen(g_config.dict_file) == 0) {
        fprintf(stderr, "错误: 字典模式需要字典文件 (-d)\n");
        print_usage(argv[0]);
    }
    if (g_config.attack_mode == ATTACK_MASK && strlen(g_config.mask) == 0) {
        fprintf(stderr, "错误: 掩码模式需要掩码字符串 (-k)\n");
        print_usage(argv[0]);
    }
    if (g_config.threads <= 0) g_config.threads = 1;
}

/* ------------------------------- 信号处理 ------------------------------- */
void signal_handler(int sig) {
    if (sig == SIGINT || sig == SIGTERM) {
        printf("\n[!] 收到中断信号，正在退出...\n");
        g_should_exit = 1;
    }
}

/* ------------------------------- 主函数 --------------------------------- */
int main(int argc, char *argv[]) {
    signal(SIGINT, signal_handler);
    parse_args(argc, argv);
    load_hashes(g_config.hash_file);
    if (strlen(g_config.rule_file) > 0)
        load_rules(g_config.rule_file);
    
    clock_t start = clock();
    run_cracker();
    clock_t end = clock();
    double elapsed = (double)(end - start) / CLOCKS_PER_SEC;
    
    printf("\n========== 结果摘要 ==========\n");
    printf("总计哈希: %d, 已破解: %d\n", g_total_hashes, g_cracked_count);
    if (g_cracked_count == g_total_hashes)
        printf("🎉 全部破解成功！\n");
    else
        printf("⚠️ 仍有 %d 个哈希未破解\n", g_total_hashes - g_cracked_count);
    printf("耗时: %.2f 秒\n", elapsed);
    
    save_results();
    
    // 清理链表
    HashNode *node = g_hash_list;
    while (node) {
        HashNode *next = node->next;
        free(node);
        node = next;
    }
    return 0;
}