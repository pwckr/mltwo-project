library(smotefamily)
library(caret)
library(ggplot2)
library(yardstick)
library(dplyr)

balance_classes_with_smote <- function(df) {
    features <- df[, !names(df) %in% "quality"]
    target <- df[["quality"]]

    # Determine the target size (size of the largest class)
    target_size <- max(table(target))

    # Initialize an empty dataframe for the balanced dataset
    balanced_df <- df[0, ]

    # Loop through each class
    for (class in unique(target)) {
        class_data <- df[target == class, ]
        num_class <- nrow(class_data)

        if (num_class < 2) {
            stop("SMOTE requires at least 2 samples of each class.")
        }

        if (nrow(class_data) < target_size) {
            # Calculate the number of synthetic samples needed
            dup_size <- ((target_size - num_class)
                / num_class)

            # Apply SMOTE
            oversampled_data <- SMOTE(features[target == class, ],
                target[target == class], K = min(5, num_class - 1), dup_size = dup_size)$data

            colnames(oversampled_data) <- colnames(balanced_df)

            # Combine the oversampled data
            balanced_df <- rbind(balanced_df, oversampled_data)
        } else {
            balanced_df <- rbind(balanced_df, class_data)
        }
    }

    balanced_df <- data.frame(lapply(balanced_df, as.numeric))

    return(balanced_df)
}

balance_classes_by_undersampling <- function(df, target_size = 0) { # nolint
    target <- df[["quality"]]

    # Determine the target size (size of the smallest class)
    if (target_size == 0) {
        target_size <- min(table(target))
    }

    # Initialize an empty dataframe for the balanced dataset
    balanced_df <- df[0, ] # Creates an empty dataframe with same columns as df

    # Loop through each class
    for (class in unique(target)) {
        class_data <- df[target == class, ]

        # Randomly sample instances if the class is larger than the target size
        if (nrow(class_data) > target_size) {
            undersampled_data <- class_data[sample(nrow(class_data),
                                             target_size), ]
        } else {
            undersampled_data <- class_data
        }

        balanced_df <- rbind(balanced_df, undersampled_data)
    }

    return(balanced_df)
}

balance_classes_hybrid_sampling <- function(df, target_size) {
    # Undersample the dataset
    undersampled_df <- balance_classes_by_undersampling(df, target_size)

    # Oversample the dataset
    balanced_df <- balance_classes_with_smote(undersampled_df)

    return(balanced_df)
}

build_weights <- function(data) {
    # Inverse frequency weightinghow 

    # Create a matrix of weights
    weights <- c(rep(1, nrow(data)))

    counts <- table(data$quality)
    total <- sum(counts)

    # Loop over the weights and data
    for (i in seq_along(weights)) {
        # Higher weight for quality that differs from the mean
        weights[i] <- (total / counts[as.character(data[i, "quality"])])
    }

    # Return the weights
    return(weights)
}

evaluate_model <- function(model, data, title = "", show_plot = TRUE) {

    # Get the predictors
    predictors <- data[, !names(data) %in% "quality", drop = FALSE]

    if ("smooth.spline" %in% class(model)) {
        # Case for smooth.spline
        predicted_values <- as.vector(predict(model, predictors)$y)
    } else {
        # Case for ppr
        predicted_values <- data.frame(predict(model, newdata = predictors))
    }

    actual <- data$quality
    predicted <- as.numeric(predicted_values[[1]])

    # Compute the MSE per class
    mse_per_class <- data.frame(
                        actual = actual,
                        predicted = predicted
                    ) %>%
                    group_by(actual) %>%
                    summarize(mse = mean((actual - predicted)^2))
    mse_vec <- mse_per_class$mse
    names(mse_vec) <- paste("MSE class", mse_per_class$actual)
    mse_per_class <- mse_vec

    # Compute the total MSE
    mse <- mean((actual - predicted)^2)

    # Print the MSE
    print(paste("MSE (", title, "): ", mse, sep = ""))

    # Print the Mean MSE of all class
    print(paste("Mean MSE over classes (", title, "): ", mean(mse_per_class), sep = ""))

    if (show_plot) {
        # Create a violin plot
        plot <- create_violin_plot(actual, predicted, title)

        # Show the plot
        print(plot)
    }

    # Return the Predicted Values, MSE Losses
    invisible(list(mse = mse, mse_per_class = mse_per_class, predicted_values = predicted))
}

create_violin_plot <- function(
    actual,
    predicted,
    title = "",
    show_loss = TRUE,
    show_abline = TRUE,
    xlab = "Actual Qualities",
    ylab = "Predicted Qualities") {

    combined_data <- data.frame(Actual = actual,
        Predicted = predicted)

    data_count <- combined_data %>%
        group_by(Actual) %>%
        summarize(count = n())

    # Calculate the median for each group
    medians <- combined_data %>%
        group_by(Actual) %>%
        summarize(median_value = median(Predicted))

    combined_data <- merge(merge(combined_data, data_count, by = "Actual"),
                            medians, by = "Actual")

    if (show_loss) {
        # Compute the MSE
        mse <- mean((actual - predicted)^2)

        # Compute the MSE per class
        mse_per_class <- data.frame(
                            actual = actual,
                            predicted = predicted
                        ) %>%
                        group_by(actual) %>%
                        summarize(mse = mean((actual - predicted)^2))
        mse_vec <- mse_per_class$mse
        names(mse_vec) <- mse_per_class$actual
        mse_per_class <- mse_vec

        plt_title <- paste(title,
                        "\nMSE: ", round(mse, digits = 2),
                        " - Mean MSE over classes: ", round(mean(mse_per_class), digits = 2))
    } else {
        plt_title <- title
    }

    # Create the violin plot
    plot <- ggplot(
                combined_data,
                aes(x = factor(Actual), y = Predicted, fill = factor(Actual))
            ) +
            geom_violin(
                trim = FALSE,
                scale = "width",
                show.legend = FALSE
            ) +
            geom_point(
                position = position_jitter(width = 0.2),
                size = 1.5,
                alpha = 0.9,
                show.legend = FALSE
            )

    if (show_abline) {
        plot <- plot +
                geom_abline(
                    slope = 1,
                    intercept = min(combined_data$Actual) - 1,
                    color = "black",
                    linewidth = 2.25,
                ) +
                geom_abline(
                    slope = 1,
                    intercept = min(combined_data$Actual) - 1,
                    color = "#3DDC84",
                    linewidth = 1.25,
                )
    }

    plot <- plot +
            geom_text(
                aes(label = count, y = median_value, hjust = 0.5),
                size = 7,
                color = "white"
            ) +
            scale_fill_brewer(palette = "Dark2"
            ) +
            labs(
                title = plt_title,
                x = xlab,
                y = ylab
            ) +
            theme(
                axis.title.x = element_text(
                    margin = margin(t = 15),
                    size = 18),
                axis.title.y = element_text(
                    margin = margin(r = 15),
                    size = 18),
                axis.text.x = element_text(
                    margin = margin(t = 10),
                    size = 14),
                axis.text.y = element_text(
                    margin = margin(r = 10),
                    size = 14),
                plot.title = element_text(
                    margin = margin(b = 20),
                    hjust = 0.5,
                    size = 22,
                    face = "bold"),
                plot.margin = margin(0.75, 0.75, 0.75, 0.75, "cm")
            )

    return(plot)
}

plot_spline_curve <- function(spline_obj, quality, predictor, title = "", xlab = "", ylab = "") { # nolint

    combined_data <- data.frame(
        Quality = quality,
        Predictor = predictor
    )

    x_values <- seq(min(predictor), max(predictor), length.out = 300)
    spline_pred <- as.vector(predict(spline_obj, x_values)$y)

    # Calculate the median for each group
    medians <- combined_data %>%
        group_by(Quality) %>%
        summarize(median_value = median(Predictor))

    count <- combined_data %>%
        group_by(Quality) %>%
        summarize(count = n())

    combined_data <- merge(combined_data, medians, by = "Quality")
    combined_data <- merge(combined_data, count, by = "Quality")

    # Create the violin plot
    plot <- ggplot(
            ) +
            geom_violin(
                data = combined_data,
                aes(x = Predictor, y = Quality, fill = factor(Quality)),
                trim = FALSE,
                scale = "width",
                show.legend = FALSE
            ) +
            geom_point(
                data = combined_data,
                aes(x = Predictor, y = Quality, fill = factor(Quality)),
                position = position_jitter(height = 0.2),
                size = 1.5,
                alpha = 0.9,
                show.legend = FALSE
            ) +
            geom_line(
                aes(x = x_values, y = spline_pred),
                color = "black",
                linewidth = 2.25
            ) +
            geom_line(
                aes(x = x_values, y = spline_pred),
                color = "skyblue",
                linewidth = 1.25
            ) +
            geom_text(
                data = combined_data,
                aes(label = count, x = median_value, y = Quality, vjust = 0.5),
                size = 7,
                color = "white"
            ) +
            scale_fill_brewer(
                palette = "Dark2"
            ) +
            labs(
                data = combined_data,
                aes(x = Predictor, y = Quality, fill = factor(Quality)),
                title = title,
                x = xlab,
                y = ylab
            ) +
            theme(
                axis.title.x = element_text(
                    margin = margin(t = 15),
                    size = 18),
                axis.title.y = element_text(
                    margin = margin(r = 15),
                    size = 18),
                axis.text.x = element_text(
                    margin = margin(t = 10),
                    size = 14),
                axis.text.y = element_text(
                    margin = margin(r = 10),
                    size = 14),
                plot.title = element_text(
                    margin = margin(b = 20),
                    hjust = 0.5,
                    size = 22,
                    face = "bold"),
                plot.margin = margin(0.75, 0.75, 0.75, 0.75, "cm")
            )

    print(plot)
    return(plot)
}

tune_spline_df <- function(train_data, val_data, predictor, weights = NULL, title = "", maxdf = 70) {

    # Get the predictors
    train_predictor <- train_data[, !names(train_data) %in% "quality", drop = FALSE]
    val_predictor <- val_data[, !names(train_data) %in% "quality", drop = FALSE]

    if (length(train_predictor[[predictor]]) != nrow(train_data)
        || length(val_predictor[[predictor]]) != nrow(val_data)) {
        stop("Length of predictor and quality columns -do not match.")
    }

    maxdf <- min(maxdf, length(unique(train_data[[predictor]])) - 1)

    df_values <- c(2:maxdf)

    # Create a vector for MSE losses
    mse <- rep(0, length(df_values))

    # Loop over the param_values
    for (i in seq_along(df_values)) {

        if (is.null(weights)) {
            args <- list(
                x = train_predictor[[predictor]],
                y = train_data$quality,
                df = df_values[i]
        )
        } else {
            args <- list(
                x = train_predictor[[predictor]],
                y = train_data$quality,
                w = weights,
                df = df_values[i]
            )
        }

        # Fit the model
        spline_obj <- do.call(smooth.spline, args, quote = TRUE)

        # Predict on the validation set
        val_spline <- as.vector(predict(spline_obj, val_predictor[[predictor]])$y)

        # Compute MSE loss
        mse[i] <- mean((val_spline - val_data$quality)^2)
    }

    # Set plot margin
    par(mar = c(5, 4, 4, 2) + 1)

    # Plot the MSE losses
    plot(seq_along(df_values), mse, type = "b", xlab = "df",
        ylab = "MSE Loss", main = paste("HPO -", title),
        cex.lab = 1.5, cex.main = 1.7, cex.axis = 1.1)

    # Highlight the minimum MSE loss
    points(which.min(mse), mse[which.min(mse)], col = "red", pch = 19)

    best_mse <- mse[which.min(mse)]
    best_df <- df_values[which.min(mse)]

    # Print the minimum MSE loss
    print(paste("Minimum MSE with df = ", best_df, ": ", best_mse))

    # Return the best MSE loss and df
    return(list(best_mse = best_mse, best_df = best_df,
        all_mse = mse))
}

get_pca_transformed_data <- function(data, pca_transform = NULL) {
    # Get the predictors
    predictors <- data[, !colnames(data) %in% "quality"]

    is_transformed <- TRUE
    # If pca_transform is not provided, fit PCA on the data
    if (is.null(pca_transform)) {
        pca_transform <- prcomp(predictors, scale. = TRUE)
        is_transformed <- FALSE
    }

    # Transform the data
    pc_scores <- as.data.frame(predict(pca_transform, predictors))

    # Rename the columns
    colnames <- list()
    for (i in 1:ncol(pc_scores)) { # nolint
        colnames[i] <- paste("PC", i, sep = "")
    }

    pca_data <- cbind(pc_scores, quality = data$quality)
    proportion_of_var <- summary(pca_transform)$importance["Proportion of Variance", ] # nolint

    if (!is_transformed) {
        # Plot the proportion of variance
        plot(proportion_of_var, type = "b", main = "Explained Variance",
            xlab = "Principal Component", ylab = "Proportion of Variance",
            cex.lab = 1.5, cex.main = 1.7, cex.axis = 1.1)
    }

    # Return the transformed data and the PCA transformation
    return(list(data = pca_data,
            transform = pca_transform,
            proportion_of_var = proportion_of_var))
}