# TODOs:
# HPO with validation set

# ---- Load data and libraries from Setup.R file -------------------------------

source("src/setup.R")
clean_up <- TRUE

# ---- Define functions --------------------------------------------------------

source("src/helper_functions.R")

# ---- Define hybrid sampled data ----------------------------------------------

target_size <- 150
# Apply sampling techniques to the training and validation sets
train_hybrid_sampled <- balance_classes_hybrid_sampling(train, target_size)
# 67 because we want to keep the same ratio between train and validation
validation_hybrid_sampled <- balance_classes_hybrid_sampling(validation, round(target_size / 3))
# Dont sample the test set

# ---- Check the class distribution ---------------------------------------------

table(train_hybrid_sampled$quality)
table(validation_hybrid_sampled$quality)

# ---- Perform PCA on the dataset ----------------------------------------------

pca_result <- get_pca_transformed_data(train)

train_pca <- pca_result$data
validation_pca <- get_pca_transformed_data(validation, pca_result$transform)$data # nolint
test_pca <- get_pca_transformed_data(test, pca_result$transform)$data

hybrid_sampled_pca_result <- get_pca_transformed_data(train_hybrid_sampled) # nolint

train_hybrid_sampled_pca <- hybrid_sampled_pca_result$data
validation_hybrid_sampled_pca <- get_pca_transformed_data(validation_hybrid_sampled, pca_result$transform)$data # nolint

# Plot PC1 vs Quality to see relationship
plot <- create_violin_plot(
            train_pca$quality,
            train_pca$PC1,
            "PC1 vs Quality",
            show_loss = FALSE,
            show_abline = FALSE,
            xlab = "Quality",
            ylab = "PC1")
print(plot)

# ---- Perform Spline smoothing simple only with HPO ---------------------------

tuning_result <- tune_spline_df(train_pca, validation_pca, "PC1",
    title = "Simple Spline on PC1")

simple_spline_name <- "Simple Spline on PC1 with HPO"
spline_simple <- smooth.spline(train_pca$PC1, train_pca$quality,
                df = tuning_result$best_df)
plot_spline_curve(spline_simple,
    train_pca$quality,
    train_pca$PC1,
    title = simple_spline_name,
    xlab = "PC1",
    ylab = "Quality")

val_results_simple <- evaluate_model(spline_simple,
    validation_pca[, c("PC1", "quality")], title = simple_spline_name)

# ---- Perform Spline smoothing weighted ---------------------------------------

weights <- build_weights(train_pca)
tuning_result <- tune_spline_df(train_pca, validation_pca, "PC1",
    weights = weights,
    title = "Inverse Frequency Weighted Spline on PC1")

weighted_spline_name <- "Inverse Frequency Weighted Spline on PC1 with HPO"
spline_weighted <- smooth.spline(train_pca$PC1,
                                 train_pca$quality,
                                 w = weights,
                                 df = tuning_result$best_df)
plot_spline_curve(spline_weighted,
    train_pca$quality,
    train_pca$PC1,
    title = weighted_spline_name,
    xlab = "PC1",
    ylab = "Quality")

val_results_weighted <- evaluate_model(spline_weighted,
    validation_pca[, c("PC1", "quality")], title = weighted_spline_name)

# ---- Perform Spline smoothing with mixed sampling ----------------------------

tuning_result <- tune_spline_df(train_hybrid_sampled_pca, validation_hybrid_sampled_pca, "PC1",
    title = "Spline on PC1 with balanced data (hybrid sampled)")

hybrid_sampled_spline_name <- "Spline on PC1 with balanced data (hybrid sampled) and HPO"
spline_mixed_sampling <- smooth.spline(train_hybrid_sampled_pca$PC1,
                                       train_hybrid_sampled_pca$quality,
                                       df = tuning_result$best_df)
plot_spline_curve(spline_mixed_sampling,
    train_pca$quality,
    train_pca$PC1,
    title = hybrid_sampled_spline_name,
    xlab = "PC1",
    ylab = "Quality")

# Transform original validation data to PCA of train_hybrid_sampled
val <- get_pca_transformed_data(validation, hybrid_sampled_pca_result$transform)$data
val_results_mixed <- evaluate_model(spline_mixed_sampling,
    val[, c("PC1", "quality")], title = hybrid_sampled_spline_name)

# ---- Perform Spline smoothing with mixed sampling and weights ----------------

weights <- build_weights(train_hybrid_sampled_pca)

tuning_result <- tune_spline_df(train_hybrid_sampled_pca, validation_hybrid_sampled_pca, "PC1",
    weights = weights,
    title = "Weighted spline on PC1 with balanced data (hybrid sampled)")

hybrid_sampled_weighted_spline_name <- "Weighted spline on PC1 with balanced data (hybrid sampled) and HPO"
spline_mixed_weighted <- smooth.spline(train_hybrid_sampled_pca$PC1,
                                                train_hybrid_sampled_pca$quality,
                                                w = weights,
                                                df = tuning_result$best_df)
plot_spline_curve(spline_mixed_weighted,
    train_pca$quality,
    train_pca$PC1,
    title = hybrid_sampled_weighted_spline_name,
    xlab = "PC1",
    ylab = "Quality")

# Transform original validation data to PCA of train_hybrid_sampled
val <- get_pca_transformed_data(validation, hybrid_sampled_pca_result$transform)$data
val_results_mixed_weighted <- evaluate_model(spline_mixed_weighted,
    val[, c("PC1", "quality")], title = hybrid_sampled_weighted_spline_name)

# ---- Create a tables with the results ----------------------------------------

# Create a list with names
model_names <- list(
    simple_spline_name,
    weighted_spline_name,
    hybrid_sampled_spline_name,
    hybrid_sampled_weighted_spline_name
)

# Create a list with the models
models <- list(
    spline_simple,
    spline_weighted,
    spline_mixed_sampling,
    spline_mixed_weighted
)
names(models) <- model_names

# Create a dataframe with the results
class_mse_vectors <- list(
    val_results_simple$mse_per_class,
    val_results_weighted$mse_per_class,
    val_results_mixed$mse_per_class,
    val_results_mixed_weighted$mse_per_class
)
names(class_mse_vectors) <- model_names

val_results <- do.call(rbind, lapply(class_mse_vectors, function(x) as.data.frame(t(x))))
rownames(val_results) <- names(class_mse_vectors)
val_results <- cbind(val_results,
                "Mean MSE over classes" = c(
                    mean(val_results_simple$mse_per_class),
                    mean(val_results_weighted$mse_per_class),
                    mean(val_results_mixed$mse_per_class),
                    mean(val_results_mixed_weighted$mse_per_class)),
                "Total MSE" = c(
                    val_results_simple$mse,
                    val_results_weighted$mse,
                    val_results_mixed$mse,
                    val_results_mixed_weighted$mse)
                )
print(val_results)

# ---- Model selection ---------------------------------------------------------

# Select the best model according to MSE over classes
min_idx <- which.min(val_results$"Mean MSE over classes")
final_model_name <- rownames(val_results)[min_idx]
final_model <- models[[final_model_name]]

if (grepl("Sampled", final_model_name)) {
    final_transform <- hybrid_sampled_pca_result$transform
} else {
    final_transform <- pca_result$transform
}

# ---- Clean up ----------------------------------------------------------------

if (clean_up) {
    rm(list = setdiff(ls(), keep_vars))
}