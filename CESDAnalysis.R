# Part 2: Investigating the Relationship Between Depression and Personality Using Machine Learning
# analysis of data created in Part 1
# by George Tzimas (Monash University), Jake Kraska (Monash University) and Shane Costello (Monash University)

# set the working directory to source file directory manually
# ensure or necessary data is in ~/data/
# data required: demog.csv, country.csv, big5.csv, cesd_item_level.csv, user-likes.csv, fb_like.csv
setwd("D:/Monash/EDF4604 Research project/01 Research Project/Thesis Analysis/Data")
getwd()

# start a clock
cat("Timer started!\n")
total.time <- proc.time()
ptm <- proc.time()

# Install necessary packages
# Only needs to be run the first time
# install.packages("moments")
# install.packages("ppcor")
# install.packages("ggplot2")
# install.packages("reshape2")
# install.packages("car")
# install.packages("StatMatch")

# Load required packages
library(moments)
library(ppcor)
library(Matrix)
library(irlba)
library(ggplot2)
library(reshape2)
library(car)
library(StatMatch)

########### create necessary function(s)

# creates a function that is used to determine accuracies
compute_accuracy <- function(original_variable, predicted_variable){
  # Computes the accuracy between two variables
  #
  # Args:
  #   original_variable: the variable gathered from questionnaire data
  #   predicted_variable: the variable created by the prediction model
  #
  # Returns:
  #   The correlation between the two inputted variables
  
  if (length(unique(na.omit(original_variable))) == 2) {
    f <- which(!is.na(original_variable))
    temp <- prediction(predicted_variable[f], original_variable[f])
    return(performance(temp,"auc")@y.values)
  } else {
    return(cor(original_variable, predicted_variable, use = "pairwise"))
  }
  rm(temp,f)
}

########### load and prepare files

# read in files
users <- read.csv("users-reduced-cesd.csv", header = TRUE)
ul <- read.csv("user-likes-cesd.csv", header = TRUE)
likes <- read.csv("fb_like.csv", header = TRUE)

# remove users that have CESD below 1
users <- users[which(users$cesd > 0),]

# remove likes from likes file that aren't in the ul file
likes <- likes[likes$like_id %in% ul$likeid,]

# Stop the clock
cat("Time taken to read in data\n")
proc.time() - ptm

# Start the clock
ptm <- proc.time()

# construct the matrix - Match entries in ul with users and likes dictionaries
ul$user_row <- match(ul$userid,users$userid)
ul$like_row <- match(ul$likeid,likes$like_id)

# remove rows that have either missing user row or missing like row
ul <- na.omit(ul)

# Construct the sparse User-Like Matrix M and check dimensions
M <- sparseMatrix(i = ul$user_row, j = ul$like_row, x = 1)

# Save user IDs as row names in M and save Like names as column names in M
rownames(M) <- users$userid
colnames(M) <- likes$name

# Remove users that have less than 10 likes and remove likes that have been liked less than 50 times
repeat {                                       # repeat whatever is in the brackets
  i <- sum(dim(M))                             # check the size of M
  M <- M[rowSums(M) >= 10, colSums(M) >= 50]  # Retain only these rows/columns that meet the threshold
  if (sum(dim(M)) == i) break                  # if the size has not changed, break the loop
}
rm(i)

# Remove the users from users object that were removed from M
users <- users[match(rownames(M), users$userid), ]

# Remove the likes from likes object that were removed from M
likes <- likes[match(colnames(M), likes$name), ]

# look at final number of users and likes
dim(users)
dim(likes)

# save final users file to csv
write.csv(users, file = "users-final-cesd.csv", row.names = FALSE)

# Stop the clock
cat("Time taken to prepare matrix\n")
proc.time() - ptm

# Start the clock
ptm <- proc.time()

########### create ope, con, ext, agr, neu and cesd scores based on users likes

# set all variables ready for predictions
set.seed(seed=68)
n_folds <- 10               # set number of folds
k <- 50                     # set k
vars <- colnames(users)[-1]	# choose variables to predict
folds <- sample(1:n_folds, size = nrow(users), replace = T) # choose a sample number
results <- data.frame(userid = users$userid, ope = numeric(nrow(users)), 
                      con = numeric(nrow(users)), ext = numeric(nrow(users)), 
                      agr = numeric(nrow(users)), neu = numeric(nrow(users)), cesd = numeric(nrow(users)))
user.svd.folds <- list()
like.svd.folds <- list()

# create k svd for each fold, create list of likes associated with that fold, and then predict value
for (fold in 1:n_folds) { 
  print(paste("Cross-validated predictions, fold:", fold))
  test <- folds == fold
  
  # SVD
  Msvd <- irlba(M[!test, ], nv = k)
  user.svd.folds[[fold]] <- Msvd$u
  like.svd.folds[[fold]] <- Msvd$v
  
  # save the plot
  jpeg(file = paste("svd-plots//fold-", fold, "-svd-plot.jpeg", sep=""))
  plot(Msvd$d)
  dev.off()
  
  # varimax-rotate the resulting SVD space
  v_rot <- unclass(varimax(Msvd$v)$loadings)
  predictors <- as.data.frame(as.matrix(M %*% v_rot))
  
  # print the Likes with the highest and lowest varimax-rotated SVD scores
  print(paste("Show Likes with highest and lowest varimax-rotated SVD scores for fold", fold, "."))
  top <- list()
  bottom <-list()
  for (i in 1:5) {
    f <- order(v_rot[ ,i])
    temp <- tail(f, n = 5)
    top[[i]]<-colnames(M)[temp]  
    temp <- head(f, n = 5)
    bottom[[i]]<-colnames(M)[temp]  
  }
  print(top)
  print(bottom)
  rm(i,top,bottom,f,temp)
  
  # produce a heatmap plot
  x <- round(cor(predictors, users[,-1], use="pairwise"),2) # get correlations only for the test group
  y <- melt(x)
  colnames(y) <- c("SVD", "Trait", "r")
  qplot(x=SVD, y=Trait, data=y, fill=r, geom="tile") +
    scale_fill_gradient2(limits=range(x), breaks=c(min(x), 0, max(x)))+
    theme(axis.text=element_text(size=6), 
          axis.title=element_text(size=10,face="bold"),
          panel.background = element_rect(fill='white', colour='white'))+
    labs(x=expression('SVD'[rot]), y=NULL)
  ggsave(filename = paste("fold-", fold, "-like-heatmap.jpeg", sep=""), 
         plot = last_plot(), device = "jpeg", path = "heatmap-plots/", scale = 1, 
         width = NA, height = NA, units = "cm", dpi = 300, limitsize = FALSE)
  rm(x,y)
  
  # build prediction model for the current fold
  for (var in vars) {
    # check if the variable is dichotomous
    if (length(unique(na.omit(users[,var]))) == 2) {    
      fit <- glm(users[,var]~., data = predictors, subset = !test, family = "binomial")
      results[[var]][test] <- predict(fit, predictors[test, ], type = "response")
      # if not a dichotomous variable
    } else {
      fit <- glm(users[,var]~., data = predictors, subset = !test)
      results[[var]][test] <- predict(fit, predictors[test, ])
    }
    print(paste(" Variable", var, "done."))
  }
}

# set vars
vars <- colnames(users)[-1]
original.vars <- c("ope", "con", "ext", "agr", "neu", "cesd")
pred.vars <- c("pred_ope", "pred_con", "pred_ext", "pred_agr", "pred_neu", "pred_cesd")

# merge new results with users and remove unnecessary variables
for (var in vars) {
  results[[paste("pred_",var,sep="")]] <- results[[var]]
}
results <- subset(results, select = c("userid",pred.vars))
users <- merge(users,results, by="userid")
rm(test,results,n_folds,k,fit,var,fold,folds,Msvd,v_rot,vars,original.vars,pred.vars)

# save results to a csv
write.csv(users, file = "results-cesd.csv", row.names = FALSE)

########### evaluate the accuracies of the predictions

original.vars <- c("ope", "con", "ext", "agr", "neu", "cesd")
accuracies.pred <- list()
for (var in original.vars) {
  original <- paste(var,sep="")
  pred <- paste("pred_",var,sep="")
  accuracies.pred[[var]] <- compute_accuracy(users[[original]], users[[pred]]) 
}
rm(original.vars,var,original,pred)

########### interpret overall dimensions

vars <- colnames(users)[-1]
original.vars <- c("ope", "con", "ext", "agr", "neu", "cesd")
pred.vars <- c("pred_ope", "pred_con", "pred_ext", "pred_agr", "pred_neu", "pred_cesd")

Msvd <- irlba(M, nv = 50)
user.svd.total <- Msvd$u
like.svd.total <- Msvd$v
jpeg(file = "svd-plots//total-svd-plot.jpeg")
plot(Msvd$d)
dev.off()
v_rot <- unclass(varimax(Msvd$v)$loadings)
predictors <- as.matrix(M %*% v_rot)
top <- list()
bottom <-list()
for (i in 1:5) {
  f <- order(v_rot[ ,i])
  temp <- tail(f, n = 10)
  top[[i]]<-colnames(M)[temp]  
  temp <- head(f, n = 10)
  bottom[[i]]<-colnames(M)[temp]  
}
print(top)
print(bottom)
x <- round(cor(predictors, users[,original.vars], use="pairwise"),2)
y <- melt(x)
colnames(y) <- c("SVD", "Trait", "r")
qplot(x=SVD, y=Trait, data=y, fill=r, geom="tile") +
  scale_fill_gradient2(limits=range(x), breaks=c(min(x), 0, max(x)))+
  theme(axis.text=element_text(size=6), 
        axis.title=element_text(size=10,face="bold"),
        panel.background = element_rect(fill='white', colour='white'))+
  labs(x=expression('SVD'[rot]), y=NULL)
ggsave(filename = "total-like-heatmap.jpeg", 
       plot = last_plot(), device = "jpeg", path = "heatmap-plots/", scale = 1, 
       width = NA, height = NA, units = "cm", dpi = 300, limitsize = FALSE)
rm(Msvd,top,bottom,x,y,temp,f,i,v_rot,vars,original.vars,pred.vars)

########### descriptives for total prediction users

vars <- colnames(users)[-1]

means <- list()
sds <- list()
maxs <- list()
mins <- list()
ranges <- list()
std.e <- list()
kurt <- list()
skew <- list()
for (var in vars) { 
  means[[var]] <- mean(users[,var])
  sds[[var]] <- sd(users[,var])
  maxs[[var]] <- max(users[,var])
  mins[[var]] <- min(users[,var])
  ranges[[var]] <- max(users[,var]) - min(users[,var])
  std.e[[var]] <- sd(users[[var]]) / sqrt(length(users[[var]]))
  kurt[[var]] <- kurtosis(users[,var])
  skew[[var]] <- skewness(users[,var])
}
print(means)
print(sds)
print(maxs)
print(mins)
print(ranges)
print(std.e)
print(kurt)
print(skew)

rm(vars,var,sds,means,maxs,mins,ranges,std.e,kurt,skew)

########## descriptives for users with country

# combine with country
country <- read.csv("country.csv", stringsAsFactors = FALSE)
userscountry <- merge(users, country, by="userid")
userscountry <- na.omit(userscountry)

as.data.frame(table(as.factor(userscountry$country)))

rm(userscountry,country)

########## merge users with gender and age and conduct descriptives

# combine with demogs
demog <- read.csv("demog.csv", stringsAsFactors = FALSE)
demog <- subset(demog, select = c("userid", "gender", "age"))
users <- merge(users, demog, by="userid")
users <- na.omit(users)

vars <- colnames(users)[-1] 

# reduce down to people between age 16 and 90
users <- users[which(users$age > 16), ]
users <- users[which(users$age < 90), ]

########### analyse accuracies for values predicted with those people that have provided a gender and are between 16-90yo

original.vars <- c("ope", "con", "ext", "agr", "neu", "cesd")
accuracies.final <- list()
for (var in original.vars) {
  original <- paste(var,sep="")
  pred <- paste("pred_",var,sep="")
  accuracies.final[[var]] <- compute_accuracy(users[[original]], users[[pred]]) 
}
rm(original.vars,var,original,pred)

########## descriptives for people that have provided a gender and are between 16-90yo

as.data.frame(table(as.factor(users$gender)))
as.data.frame(table(as.factor(users$age)))

means <- list()
sds <- list()
maxs <- list()
mins <- list()
ranges <- list()
std.e <- list()
kurt <- list()
skew <- list()
for (var in vars) { 
  means[[var]] <- mean(users[,var])
  sds[[var]] <- sd(users[,var])
  maxs[[var]] <- max(users[,var])
  mins[[var]] <- min(users[,var])
  ranges[[var]] <- max(users[,var]) - min(users[,var])
  std.e[[var]] <- sd(users[[var]]) / sqrt(length(users[[var]]))
  kurt[[var]] <- kurtosis(users[,var])
  skew[[var]] <- skewness(users[,var])
}
print(means)
print(sds)
print(maxs)
print(mins)
print(ranges)
print(std.e)
print(kurt)
print(skew)

rm(vars,var,sds,means,maxs,mins,ranges,std.e,kurt,skew)

########## recreate matrix for those people between 16 and 90

# clean data
ul <- ul[ul$userid %in% users$userid,]
likes <- likes[likes$like_id %in% ul$likeid,]

# construct the matrix - Match entries in ul with users and likes dictionaries
ul$user_row <- match(ul$userid,users$userid)
ul$like_row <- match(ul$likeid,likes$like_id)

# remove rows that have either missing user row or missing like row
ul <- na.omit(ul)

# Construct the sparse User-Like Matrix M
M <- sparseMatrix(i = ul$user_row, j = ul$like_row, x = 1)

# Save user IDs as row names in M and save Like names as column names in M
rownames(M) <- users$userid
colnames(M) <- likes$name

########### examine the accuracy across different values of k with those people that have provided a gender and are between 16-90yo

orig.vars <- c("ope", "con", "ext", "agr", "neu", "cesd")
Msvd <- irlba(M, nv = 50)
for (var in orig.vars) {
  ks <- c(2:10,15,20,30,40,50) # different ks
  rs <- list()	# empty list to hold accuracies
  for (k in ks){
    # Varimax rotate Like SVD dimensions 1 to k
    accuracies.v_rot <- unclass(varimax(Msvd$v[, 1:k])$loadings)
    accuracies.predictors <- as.data.frame(as.matrix(M %*% accuracies.v_rot))
    accuracies.var.fit <- glm(users[[var]]~., data = accuracies.predictors)
    accuracies.var.pred <- predict(accuracies.var.fit, accuracies.predictors)
    
    # Save the resulting correlation coefficient as the element of R called k
    rs[[as.character(k)]] <- cor(users[[var]], accuracies.var.pred)
  }
  rs # check the results
  
  # plot the accuracy across k
  data<-data.frame(k=ks, r=as.numeric(rs))
  ggplot(data=data, aes(x=k, y=r, group=1)) + 
    theme_light() +
    stat_smooth(colour="red", linetype="dashed", size=1,se=F) + 
    geom_point(colour="red", size=2, shape=21, fill="white") +
    scale_y_continuous(breaks = seq(0, .5, by = 0.05))
  ggsave(filename = paste(var, "-accuracy-plot.jpeg", sep=""), 
         plot = last_plot(), device = "jpeg", path = "accuracy-plots/", scale = 1, 
         width = NA, height = NA, units = "cm", dpi = 300, limitsize = FALSE)
}
rm(Msvd,data,rs,ks,k,var,orig.vars,accuracies.v_rot,accuracies.predictors,accuracies.var.fit,accuracies.var.pred)

########### create regression model with those people that have provided a gender and are between 16-90yo

# Linear model for the collected data
original.lm <- glm(formula = cesd ~ ope + con + ext + agr + neu, data = users)
summary(original.lm)
confint(original.lm, level=0.95)
anova(original.lm)
vcov(original.lm) 

# Linear model for the pred created data
pred.lm <- glm(pred_cesd ~ pred_ext + pred_neu + pred_con + pred_agr + pred_ope, data = users)
summary(pred.lm)
confint(pred.lm, level=0.95)
anova(pred.lm)
vcov(pred.lm)

########### evaluate model created

#FIND VIF FOR MULTICOLLINEARITY (SHOULD BE LESS THAN 10)
vif(original.lm)
vif(pred.lm)

#FIND MAX MAHAL DISTANCE FOR OUTLIERS
finalnum <- subset(users, select = c("cesd", "ope", "con", "ext", "agr", "neu", "pred_cesd", "pred_ope", "pred_con", "pred_ext", "pred_agr", "pred_neu"))
mahal <- mahalanobis.dist(finalnum, data.y=NULL, vc=NULL)
max(mahal)

#CRITICAL VALUE = 32.909 (IVS FOR ORIG & ML = 12)

#FIND MAX COOKS D FOR BOTH REG MODELS - WANT TO NOT EXCEED 1
cooks.original <- cooks.distance(original.lm)
max(cooks.original)
rm(cooks.original)
cooks.pred <- cooks.distance(pred.lm)
max(cooks.pred)
rm(cooks.pred)

#FIND SEMI PARTIAL CORRELATIONS - REMOVE ALL NON-NUMERIC VARIABLES FROM DATA SET
spcor(finalnum, method=c("pearson"))

# rm(finalnum)

# Stop the clock
cat("Time taken to complete analysis\n")
proc.time() - ptm

cat("Time taken to complete entire code\n")
proc.time() - total.time

# rm(ptm,total.time)
