<!doctype html>
<html <?php language_attributes(); ?>>
<meta charset="<?php bloginfo('charset'); ?>">
<title><?php bloginfo('name'); ?></title>
<main>
<h1><?php bloginfo('name'); ?></h1>
<?php while (have_posts()) : the_post(); ?>
    <article>
        <h2><a href="<?php the_permalink(); ?>"><?php the_title(); ?></a></h2>
        <?php the_content(); ?>
    </article>
<?php endwhile; ?>
</main>
</html>
