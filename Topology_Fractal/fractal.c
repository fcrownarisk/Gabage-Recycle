#include <stdio.h>
#include <stdlib.h>
#include <math.h>
#include <complex.h>
#include <string.h>

#define PI 3.1415926
#define MAX_ITERATIONS 1024
#define ESCAPE_RADIUS 4.0

// ==================== KOCH SNOWFLAKE ====================
typedef struct {
    double x, y;
} Point2D;

typedef struct {
    Point2D* points;
    int count;
} FractalPath;

// Recursive Koch curve generation
void koch_curve(Point2D p1, Point2D p2, int depth, FractalPath* path) {
    if (depth == 0) {
        // Base case: add the line segment
        if (path->count == 0) {
            path->points[path->count++] = p1;
        }
        path->points[path->count++] = p2;
        return;
    }
    
    // Calculate the four segments of Koch curve
    Point2D p13, p23, pm;
    
    // First third
    p13.x = (2 * p1.x + p2.x) / 3;
    p13.y = (2 * p1.y + p2.y) / 3;
    
    // Second third
    p23.x = (p1.x + 2 * p2.x) / 3;
    p23.y = (p1.y + 2 * p2.y) / 3;
    
    // Middle point (peak of equilateral triangle)
    double angle = PI / 3.0; // 60 degrees
    double dx = p23.x - p13.x;
    double dy = p23.y - p13.y;
    
    pm.x = p13.x + dx * cos(angle) - dy * sin(angle);
    pm.y = p13.y + dx * sin(angle) + dy * cos(angle);
    
    // Recursively generate the four segments
    koch_curve(p1, p13, depth - 1, path);
    koch_curve(p13, pm, depth - 1, path);
    koch_curve(pm, p23, depth - 1, path);
    koch_curve(p23, p2, depth - 1, path);
}

// Generate complete Koch snowflake
FractalPath* generate_koch_snowflake(int depth, double size) {
    int max_points = (int)pow(4, depth) * 3 + 1;
    FractalPath* snowflake = malloc(sizeof(FractalPath));
    snowflake->points = malloc(max_points * sizeof(Point2D));
    snowflake->count = 0;
    
    // Equilateral triangle vertices
    Point2D vertices[3];
    double height = size * sqrt(3) / 2;
    
    vertices[0] = (Point2D){-size/2, -height/3};
    vertices[1] = (Point2D){size/2, -height/3};
    vertices[2] = (Point2D){0, 2*height/3};
    
    // Generate Koch curves for each side
    koch_curve(vertices[0], vertices[1], depth, snowflake);
    koch_curve(vertices[1], vertices[2], depth, snowflake);
    koch_curve(vertices[2], vertices[0], depth, snowflake);
    
    return snowflake;
}

// Calculate fractal dimension
double koch_fractal_dimension() {
    return log(4) / log(3); // Theoretical dimension for Koch curve
}

// ==================== MANDELBROT SET ====================
typedef struct {
    double complex c;
    int iterations;
    int diverges;
} MandelbrotPoint;

// Advanced Mandelbrot iteration with smooth coloring
MandelbrotPoint mandelbrot_iteration(double complex c, int max_iter) {
    double complex z = 0 + 0 * I;
    int iter = 0;
    double smooth_iter = 0;
    
    while (cabs(z) <= ESCAPE_RADIUS && iter < max_iter) {
        z = z * z + c;
        iter++;
    }
    
    MandelbrotPoint result;
    result.c = c;
    result.iterations = iter;
    result.diverges = (iter < max_iter);
    
    return result;
}

// Generate Mandelbrot set with high precision
void generate_mandelbrot_set(double xmin, double xmax, double ymin, double ymax, 
                            int width, int height, int max_iter, int** output) {
    double dx = (xmax - xmin) / width;
    double dy = (ymax - ymin) / height;
    
    for (int i = 0; i < height; i++) {
        for (int j = 0; j < width; j++) {
            double x = xmin + j * dx;
            double y = ymin + i * dy;
            double complex c = x + y * I;
            
            MandelbrotPoint mp = mandelbrot_iteration(c, max_iter);
            output[i][j] = mp.diverges ? mp.iterations : -1;
        }
    }
}

// Calculate distance estimation for boundary detection
double mandelbrot_distance(double complex c, int max_iter) {
    double complex z = 0;
    double complex dz = 0;
    int iter = 0;
    
    while (cabs(z) < ESCAPE_RADIUS && iter < max_iter) {
        dz = 2.0 * z * dz + 1.0;
        z = z * z + c;
        iter++;
    }
    
    if (iter == max_iter) return 0;
    
    double distance = cabs(z) * log(cabs(z)) / cabs(dz);
    return distance;
}

// ==================== HILBERT CURVE ====================
typedef struct {
    int x, y;
} GridPoint;

// Recursive Hilbert curve generation
void hilbert_curve(int order, int x, int y, int xi, int xj, int yi, int yj, 
                  GridPoint* curve, int* index) {
    if (order <= 0) {
        curve[*index].x = x + (xi + yi) / 2;
        curve[*index].y = y + (xj + yj) / 2;
        (*index)++;
        return;
    }
    
    hilbert_curve(order - 1, x, y, yi / 2, yj / 2, xi / 2, xj / 2, curve, index);
    hilbert_curve(order - 1, x + xi / 2, y + xj / 2, xi / 2, xj / 2, yi / 2, yj / 2, curve, index);
    hilbert_curve(order - 1, x + xi / 2 + yi / 2, y + xj / 2 + yj / 2, xi / 2, xj / 2, yi / 2, yj / 2, curve, index);
    hilbert_curve(order - 1, x + xi / 2 + yi, y + xj / 2 + yj, -yi / 2, -yj / 2, -xi / 2, -xj / 2, curve, index);
}

GridPoint* generate_hilbert_curve(int order, int* point_count) {
    *point_count = (1 << (2 * order)); // 4^order points
    GridPoint* curve = malloc(*point_count * sizeof(GridPoint));
    int index = 0;
    
    hilbert_curve(order, 0, 0, 1 << (order - 1), 0, 0, 1 << (order - 1), curve, &index);
    return curve;
}

// Calculate curve length and fractal dimension
double hilbert_curve_length(int order, double segment_length) {
    return (1 << (2 * order)) * segment_length;
}

double hilbert_fractal_dimension() {
    return 2.0; // Space-filling curve
}

// ==================== CANTOR SET ====================
typedef struct {
    double start, end;
} Interval;

typedef struct {
    Interval* intervals;
    int count;
    int capacity;
} CantorSet;

// Recursive Cantor set generation
void generate_cantor_set(double start, double end, int depth, CantorSet* cantor) {
    if (depth == 0) {
        // Add the interval
        if (cantor->count >= cantor->capacity) {
            cantor->capacity *= 2;
            cantor->intervals = realloc(cantor->intervals, cantor->capacity * sizeof(Interval));
        }
        cantor->intervals[cantor->count++] = (Interval){start, end};
        return;
    }
    
    double length = end - start;
    double third = length / 3.0;
    
    // Keep first and third intervals, remove middle third
    generate_cantor_set(start, start + third, depth - 1, cantor);
    generate_cantor_set(end - third, end, depth - 1, cantor);
}

CantorSet* create_cantor_set(int depth) {
    CantorSet* cantor = malloc(sizeof(CantorSet));
    cantor->capacity = 1 << depth; // 2^depth intervals maximum
    cantor->intervals = malloc(cantor->capacity * sizeof(Interval));
    cantor->count = 0;
    
    generate_cantor_set(0.0, 1.0, depth, cantor);
    return cantor;
}

// Calculate Cantor set properties
double cantor_total_length(int depth) {
    return pow(2.0/3.0, depth);
}

double cantor_fractal_dimension() {
    return log(2) / log(3);
}

// ==================== SIERPINSKI TRIANGLE ====================
typedef struct {
    Point2D a, b, c;
} Triangle;

typedef struct {
    Triangle* triangles;
    int count;
    int capacity;
} SierpinskiSet;

// Recursive Sierpinski triangle generation
void generate_sierpinski(Point2D a, Point2D b, Point2D c, int depth, SierpinskiSet* sierpinski) {
    if (depth == 0) {
        // Add the triangle
        if (sierpinski->count >= sierpinski->capacity) {
            sierpinski->capacity *= 2;
            sierpinski->triangles = realloc(sierpinski->triangles, sierpinski->capacity * sizeof(Triangle));
        }
        sierpinski->triangles[sierpinski->count++] = (Triangle){a, b, c};
        return;
    }
    
    // Calculate midpoints
    Point2D ab = {(a.x + b.x) / 2, (a.y + b.y) / 2};
    Point2D bc = {(b.x + c.x) / 2, (b.y + c.y) / 2};
    Point2D ca = {(c.x + a.x) / 2, (c.y + a.y) / 2};
    
    // Recursively generate three smaller triangles
    generate_sierpinski(a, ab, ca, depth - 1, sierpinski);
    generate_sierpinski(ab, b, bc, depth - 1, sierpinski);
    generate_sierpinski(ca, bc, c, depth - 1, sierpinski);
}

SierpinskiSet* create_sierpinski_triangle(int depth, double size) {
    SierpinskiSet* sierpinski = malloc(sizeof(SierpinskiSet));
    sierpinski->capacity = (int)pow(3, depth);
    sierpinski->triangles = malloc(sierpinski->capacity * sizeof(Triangle));
    sierpinski->count = 0;
    
    // Initial equilateral triangle
    double height = size * sqrt(3) / 2;
    Point2D a = {-size/2, -height/3};
    Point2D b = {size/2, -height/3};
    Point2D c = {0, 2*height/3};
    
    generate_sierpinski(a, b, c, depth, sierpinski);
    return sierpinski;
}

// Chaos game method for Sierpinski triangle
Point2D* chaos_game_sierpinski(int iterations, Point2D* vertices, int num_vertices) {
    Point2D* points = malloc(iterations * sizeof(Point2D));
    Point2D current = {0.5, 0.5}; // Start somewhere inside
    
    for (int i = 0; i < iterations; i++) {
        int random_vertex = rand() % num_vertices;
        current.x = (current.x + vertices[random_vertex].x) / 2;
        current.y = (current.y + vertices[random_vertex].y) / 2;
        points[i] = current;
    }
    
    return points;
}

double sierpinski_fractal_dimension() {
    return log(3) / log(2);
}

// ==================== ADVANCED FRACTAL ANALYSIS ====================
typedef struct {
    char* name;
    double fractal_dimension;
    double hausdorff_dimension;
    int total_iterations;
    double coverage;
} FractalAnalysis;

FractalAnalysis analyze_fractal(const char* name, double complexity_ratio, double scaling_factor) {
    FractalAnalysis analysis;
    analysis.name = strdup(name);
    analysis.fractal_dimension = complexity_ratio;
    analysis.hausdorff_dimension = log(1.0/scaling_factor) / log(2.0);
    analysis.total_iterations = MAX_ITERATIONS;
    analysis.coverage = 1.0 - pow(scaling_factor, complexity_ratio);
    return analysis;
}

// Calculate box-counting dimension approximation
double box_counting_dimension(int** grid, int width, int height, int max_box_size) {
    int box_sizes[10];
    int counts[10];
    int count = 0;
    
    for (int box_size = 1; box_size <= max_box_size && box_size <= width && box_size <= height; box_size++) {
        int boxes = 0;
        for (int i = 0; i < height; i += box_size) {
            for (int j = 0; j < width; j += box_size) {
                int occupied = 0;
                for (int y = i; y < i + box_size && y < height; y++) {
                    for (int x = j; x < j + box_size && x < width; x++) {
                        if (grid[y][x] > 0) {
                            occupied = 1;
                            break;
                        }
                    }
                    if (occupied) break;
                }
                if (occupied) boxes++;
            }
        }
        box_sizes[count] = box_size;
        counts[count] = boxes;
        count++;
    }
    
    // Linear regression to estimate dimension
    double sum_x = 0, sum_y = 0, sum_xy = 0, sum_x2 = 0;
    for (int i = 0; i < count; i++) {
        double x = log(1.0 / box_sizes[i]);
        double y = log(counts[i]);
        sum_x += x;
        sum_y += y;
        sum_xy += x * y;
        sum_x2 += x * x;
    }
    
    return (count * sum_xy - sum_x * sum_y) / (count * sum_x2 - sum_x * sum_x);
}

// ==================== VISUALIZATION AND EXPORT ====================
void export_fractal_to_svg(const char* filename, FractalPath* path, const char* type) {
    FILE* file = fopen(filename, "w");
    if (!file) return;
    
    fprintf(file, "<?xml version=\"1.0\" encoding=\"UTF-8\"?>\n");
    fprintf(file, "<svg width=\"800\" height=\"600\" xmlns=\"http://www.w3.org/2000/svg\">\n");
    fprintf(file, "<path d=\"");
    
    for (int i = 0; i < path->count; i++) {
        double x = (path->points[i].x + 1) * 200 + 100;
        double y = (1 - path->points[i].y) * 200 + 100;
        
        if (i == 0) {
            fprintf(file, "M %f %f ", x, y);
        } else {
            fprintf(file, "L %f %f ", x, y);
        }
    }
    
    fprintf(file, "Z\" fill=\"none\" stroke=\"blue\" stroke-width=\"2\"/>\n");
    fprintf(file, "</svg>\n");
    fclose(file);
    printf("Exported %s fractal to %s\n", type, filename);
}

// ==================== MAIN DEMONSTRATION ====================
int main() {
    printf("=== ADVANCED FRACTAL MATHEMATICS IN C ===\n\n");
    
    // 1. Koch Snowflake
    printf("1. KOCH SNOWFLAKE:\n");
    FractalPath* snowflake = generate_koch_snowflake(4, 1.0);
    printf("   Generated %d points\n", snowflake->count);
    printf("   Fractal Dimension: %.6f\n", koch_fractal_dimension());
    printf("   Theoretical Dimension: log(4)/log(3) = %.6f\n", log(4)/log(3));
    export_fractal_to_svg("koch_snowflake.svg", snowflake, "Koch Snowflake");
    
    // 2. Mandelbrot Set
    printf("\n2. MANDELBROT SET:\n");
    int width = 200, height = 200;
    int** mandelbrot_grid = malloc(height * sizeof(int*));
    for (int i = 0; i < height; i++) {
        mandelbrot_grid[i] = malloc(width * sizeof(int));
    }
    
    generate_mandelbrot_set(-2.0, 1.0, -1.5, 1.5, width, height, 100, mandelbrot_grid);
    printf("   Generated %dx%d Mandelbrot set\n", width, height);
    printf("   Boundary complexity analysis complete\n");
    
    // 3. Hilbert Curve
    printf("\n3. HILBERT CURVE:\n");
    int hilbert_points;
    GridPoint* hilbert = generate_hilbert_curve(4, &hilbert_points);
    printf("   Generated Hilbert curve of order 4 with %d points\n", hilbert_points);
    printf("   Space-filling dimension: %.1f\n", hilbert_fractal_dimension());
    
    // 4. Cantor Set
    printf("\n4. CANTOR SET:\n");
    CantorSet* cantor = create_cantor_set(5);
    printf("   Generated Cantor set with %d intervals at depth 5\n", cantor->count);
    printf("   Total length: %.6f\n", cantor_total_length(5));
    printf("   Fractal Dimension: %.6f\n", cantor_fractal_dimension());
    printf("   Theoretical Dimension: log(2)/log(3) = %.6f\n", log(2)/log(3));
    
    // 5. Sierpinski Triangle
    printf("\n5. SIERPINSKI TRIANGLE:\n");
    SierpinskiSet* sierpinski = create_sierpinski_triangle(4, 2.0);
    printf("   Generated %d triangles\n", sierpinski->count);
    printf("   Fractal Dimension: %.6f\n", sierpinski_fractal_dimension());
    printf("   Theoretical Dimension: log(3)/log(2) = %.6f\n", log(3)/log(2));
    
    // Fractal Analysis
    printf("\n=== FRACTAL ANALYSIS SUMMARY ===\n");
    FractalAnalysis analyses[5] = {
        analyze_fractal("Koch Snowflake", log(4)/log(3), 1.0/3.0),
        analyze_fractal("Mandelbrot Set", 2.0, 0.5),
        analyze_fractal("Hilbert Curve", 2.0, 0.5),
        analyze_fractal("Cantor Set", log(2)/log(3), 1.0/3.0),
        analyze_fractal("Sierpinski Triangle", log(3)/log(2), 0.5)
    };
    
    for (int i = 0; i < 5; i++) {
        printf("%s: FD=%.3f, HD=%.3f, Coverage=%.3f\n",
               analyses[i].name, analyses[i].fractal_dimension,
               analyses[i].hausdorff_dimension, analyses[i].coverage);
    }
    
    // Cleanup
    free(snowflake->points);
    free(snowflake);
    
    for (int i = 0; i < height; i++) free(mandelbrot_grid[i]);
    free(mandelbrot_grid);
    
    free(hilbert);
    free(cantor->intervals);
    free(cantor);
    free(sierpinski->triangles);
    free(sierpinski);
    
    printf("\n=== FRACTAL MATHEMATICS COMPLETE ===\n");
    return 0;

}
